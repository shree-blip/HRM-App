import '../../../core/supabase/supabase_client.dart';
import 'leave_models.dart';

/// Leave Management data access. RLS scopes which rows managers can see.
/// No schema changes; balance deduction stays handled by the existing DB
/// trigger on approval.
class LeaveRepository {
  static const _cols =
      'id, user_id, leave_type, start_date, end_date, days, reason, status, '
      'approved_by, approved_at, rejection_reason, is_half_day, '
      'half_day_period, created_at';

  String get _uid => supabase.auth.currentUser!.id;

  Future<List<LeaveRequest>> myRequests() async {
    final rows = await supabase
        .from('leave_requests')
        .select(_cols)
        .eq('user_id', _uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => LeaveRequest.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<LeaveBalance>> balances() async {
    final year = DateTime.now().year;
    final rows = await supabase
        .from('leave_balances')
        .select('leave_type, total_days, used_days')
        .eq('user_id', _uid)
        .eq('year', year);
    return (rows as List)
        .map((r) => LeaveBalance.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Requests from OTHER users for the approval view. Pass [scopeUserIds] to
  /// limit a non-VP manager to their team (web useLeaveRequests
  /// fetchPendingForManager / fetchAllTeamRequests); employee names resolved
  /// from profiles.
  Future<List<LeaveRequest>> teamRequests({List<String>? scopeUserIds}) async {
    if (scopeUserIds != null && scopeUserIds.isEmpty) return const [];
    var query = supabase
        .from('leave_requests')
        .select(_cols)
        .neq('user_id', _uid);
    if (scopeUserIds != null) {
      query = query.inFilter('user_id', scopeUserIds);
    }
    final rows = await query.order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => LeaveRequest.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) return list;

    final ids = list.map((r) => r.userId).toSet().toList();
    final names = <String, String>{};
    final emails = <String, String>{};
    final profs = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name, email')
        .inFilter('user_id', ids);
    for (final p in profs as List) {
      final m = p as Map;
      names[m['user_id'] as String] =
          '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      if (m['email'] != null) emails[m['user_id'] as String] = m['email'] as String;
    }
    return list
        .map((r) => r.copyWith(
              employeeName: names[r.userId] ?? 'Employee',
              employeeEmail: emails[r.userId] ?? '',
            ),)
        .toList();
  }

  /// Inserts a pending leave request, then best-effort notifies managers.
  Future<void> submitRequest({
    required String leaveType,
    required String startDate,
    required String endDate,
    required double days,
    required String reason,
    bool isHalfDay = false,
    String? halfDayPeriod,
  }) async {
    final uid = _uid;
    final inserted = await supabase
        .from('leave_requests')
        .insert({
          'user_id': uid,
          'leave_type': leaveType,
          'start_date': startDate,
          'end_date': endDate,
          'days': days,
          'reason': reason,
          'status': 'pending',
          'is_half_day': isHalfDay,
          'half_day_period': halfDayPeriod,
        })
        .select('id')
        .single();
    final requestId = inserted['id'] as String;

    await _notifyManagers(uid);
    // Best-effort email pipeline (no-op if targets can't be resolved).
    try {
      await supabase.functions.invoke('send-leave-notification', body: {
        'leave_request_id': requestId,
        'event_type': 'submitted',
        'leave_type': leaveType,
        'start_date': startDate,
        'end_date': endDate,
        'days': days,
        'reason': reason,
        'requesting_user_id': uid,
      },);
    } catch (_) {}
  }

  Future<void> approve(LeaveRequest req) async {
    await supabase.from('leave_requests').update({
      'status': 'approved',
      'approved_by': _uid,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      'rejection_reason': null,
    }).eq('id', req.id);
    await _notifyEmployee(req, approved: true);
  }

  Future<void> reject(LeaveRequest req, String reason) async {
    await supabase.from('leave_requests').update({
      'status': 'rejected',
      'approved_by': _uid,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      'rejection_reason': reason,
    }).eq('id', req.id);
    await _notifyEmployee(req, approved: false, reason: reason);
  }

  /// Employees an admin can assign leave to — every profile with an auth
  /// account, ordered by first name (web AdminLeaveDialog.fetchEmployees).
  Future<List<({String userId, String name})>> assignableEmployees() async {
    final rows = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name')
        .not('user_id', 'is', null)
        .order('first_name', ascending: true);
    return (rows as List)
        .map((r) {
          final m = r as Map;
          return (
            userId: (m['user_id'] ?? '') as String,
            name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
          );
        })
        .where((e) => e.userId.isNotEmpty)
        .toList();
  }

  /// Admin/VP assigns leave on behalf of an employee — auto-approved. Mirrors
  /// the web adminCreateLeave: inserts an approved leave_requests row with the
  /// "[Admin assigned] " reason prefix (balance deduction is handled by the
  /// auto_deduct_leave_balance DB trigger, NOT the client), then emails the
  /// employee via send-leave-notification (event_type admin_assigned).
  Future<void> adminCreateLeave({
    required String targetUserId,
    required String leaveType,
    required String startDate, // YYYY-MM-DD
    required String endDate, // YYYY-MM-DD
    required double days,
    required String reason,
    required bool isHalfDay,
    String? halfDayPeriod,
  }) async {
    await supabase.from('leave_requests').insert({
      'user_id': targetUserId,
      'leave_type': leaveType,
      'start_date': startDate,
      'end_date': endDate,
      'days': days,
      'reason': '[Admin assigned] $reason',
      'status': 'approved',
      'approved_by': _uid,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
      'is_half_day': isHalfDay,
      'half_day_period': halfDayPeriod,
    });
    // Email — same edge function + payload as the web adminCreateLeave.
    try {
      final admin = await supabase
          .from('profiles')
          .select('first_name, last_name')
          .eq('user_id', _uid)
          .maybeSingle();
      final adminName = admin != null
          ? '${admin['first_name'] ?? ''} ${admin['last_name'] ?? ''}'.trim()
          : 'Admin';
      final emp = await supabase
          .from('profiles')
          .select('first_name, last_name, email')
          .eq('user_id', targetUserId)
          .maybeSingle();
      final employeeName = emp != null
          ? '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim()
          : 'Employee';
      final employeeEmail = (emp?['email'] ?? '') as String;
      await supabase.functions.invoke('send-leave-notification', body: {
        'leave_request_id': 'admin-assigned',
        'event_type': 'admin_assigned',
        'employee_name': employeeName,
        'employee_email': employeeEmail,
        'admin_name': adminName.isEmpty ? 'Admin' : adminName,
        'leave_type': leaveType,
        'start_date': startDate,
        'end_date': endDate,
        'days': days,
        'reason': reason,
        'target_user_ids': [targetUserId],
        'target_emails': [if (employeeEmail.isNotEmpty) employeeEmail],
        'requesting_user_id': _uid,
      },);
    } catch (_) {}
  }

  Future<void> _notifyEmployee(
    LeaveRequest req, {
    required bool approved,
    String? reason,
  }) async {
    try {
      await supabase.rpc('create_notification', params: {
        'p_user_id': req.userId,
        'p_title': approved ? '✅ Leave Approved' : '❌ Leave Rejected',
        'p_message': approved
            ? 'Your ${req.leaveType} (${req.startDate} → ${req.endDate}) was approved.'
            : 'Your ${req.leaveType} request was rejected${reason != null ? ': $reason' : ''}.',
        'p_type': 'leave',
        'p_link': '/leave',
      },);
    } catch (_) {}
    try {
      await supabase.functions.invoke('send-leave-notification', body: {
        'leave_request_id': req.id,
        'event_type': approved ? 'approved' : 'rejected',
        'leave_type': req.leaveType,
        'start_date': req.startDate,
        'end_date': req.endDate,
        'days': req.days,
        if (reason != null) 'rejection_reason': reason,
        'target_user_ids': [req.userId],
      },);
    } catch (_) {}
  }

  Future<void> _notifyManagers(String uid) async {
    try {
      final empId =
          await supabase.rpc('get_employee_id_for_user', params: {'_user_id': uid});
      if (empId is! String) return;
      final tm = await supabase
          .from('team_members')
          .select('manager_employee_id')
          .eq('member_employee_id', empId);
      final mgrEmpIds = (tm as List)
          .map((r) => (r as Map)['manager_employee_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      if (mgrEmpIds.isEmpty) return;
      final emps = await supabase
          .from('employees')
          .select('profile_id')
          .inFilter('id', mgrEmpIds);
      final profileIds = (emps as List)
          .map((r) => (r as Map)['profile_id'] as String?)
          .whereType<String>()
          .toList();
      if (profileIds.isEmpty) return;
      final profs = await supabase
          .from('profiles')
          .select('user_id')
          .inFilter('id', profileIds);
      for (final p in profs as List) {
        final mUid = (p as Map)['user_id'] as String?;
        if (mUid == null) continue;
        await supabase.rpc('create_notification', params: {
          'p_user_id': mUid,
          'p_title': '🌴 Leave Request',
          'p_message': 'A team member submitted a leave request for approval.',
          'p_type': 'leave',
          'p_link': '/approvals',
        },);
      }
    } catch (_) {}
  }
}
