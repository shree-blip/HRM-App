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

  /// Requests from OTHER users that the current user can see (RLS scopes to
  /// team for line managers/supervisors, org-wide for VP/Admin). Used by the
  /// approval view; employee names resolved from profiles.
  Future<List<LeaveRequest>> teamRequests() async {
    final rows = await supabase
        .from('leave_requests')
        .select(_cols)
        .neq('user_id', _uid)
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => LeaveRequest.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) return list;

    final ids = list.map((r) => r.userId).toSet().toList();
    final names = <String, String>{};
    final profs = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name')
        .inFilter('user_id', ids);
    for (final p in profs as List) {
      final m = p as Map;
      names[m['user_id'] as String] =
          '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    }
    return list
        .map((r) => r.copyWith(employeeName: names[r.userId] ?? 'Employee'))
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
