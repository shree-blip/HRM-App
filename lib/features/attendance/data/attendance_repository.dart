import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/attendance_time.dart';
import 'adjustment_models.dart';
import 'attendance_models.dart';

/// Read + clock-action data access for attendance. Clocking goes through the
/// server-authoritative `attendance-clock` edge function (the server owns the
/// time); everything else is RLS-scoped reads. No schema changes.
class AttendanceRepository {
  static const _logCols =
      'id, user_id, employee_id, clock_in, clock_out, break_start, break_end, '
      'total_break_minutes, pause_start, pause_end, total_pause_minutes, '
      'status, work_mode, clock_type, location_name, is_edited';

  /// Invokes the edge function for a clock action. Returns the resulting log
  /// (null when the action closes the shift, e.g. clock_out).
  Future<AttendanceLog?> clock(
    String action, {
    String? clockType,
    String? workMode,
    String? locationName,
    String? logId,
    String? newWorkMode,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      if (clockType != null) 'clock_type': clockType,
      if (workMode != null) 'work_mode': workMode,
      if (locationName != null) 'location_name': locationName,
      if (logId != null) 'log_id': logId,
      if (newWorkMode != null) 'new_work_mode': newWorkMode,
      // Sent for server-side drift detection only; server never uses it as time.
      'client_timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    final res = await supabase.functions.invoke('attendance-clock', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    final logMap = (data is Map) ? data['log'] : null;
    if (logMap == null) return null;
    return AttendanceLog.fromMap((logMap as Map).cast<String, dynamic>());
  }

  /// The user's current open log (clock_out is null), if any.
  Future<AttendanceLog?> openLog(String userId) async {
    final rows = await supabase
        .from('attendance_logs')
        .select(_logCols)
        .eq('user_id', userId)
        .isFilter('clock_out', null)
        .order('clock_in', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return AttendanceLog.fromMap((list.first as Map).cast<String, dynamic>());
  }

  /// Logs for the current NPT month (used for stats + history).
  Future<List<AttendanceLog>> monthLogs(String userId) async {
    final rows = await supabase
        .from('attendance_logs')
        .select(_logCols)
        .eq('user_id', userId)
        .gte('clock_in', NptTime.nptMonthStartUtc().toIso8601String())
        .order('clock_in', ascending: false);
    return (rows as List)
        .map((r) => AttendanceLog.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  AttendanceStats statsFrom(List<AttendanceLog> logs) {
    final nowUtc = DateTime.now().toUtc();
    final today = NptTime.todayKey();
    final weekStart = NptTime.nptWeekStartUtc();
    var t = 0.0, w = 0.0, m = 0.0;
    for (final l in logs) {
      final net = l.netHours(nowUtc: nowUtc);
      if (l.clockOut != null) m += net; // month = completed only (matches web)
      if (NptTime.nptDateKey(l.clockIn) == today) t += net;
      if (!l.clockIn.isBefore(weekStart)) w += net;
    }
    return AttendanceStats(today: t, week: w, month: m);
  }

  Future<List<BreakSession>> breakSessions(String logId) async {
    final rows = await supabase
        .from('attendance_break_sessions')
        .select('id, session_type, start_time, end_time, duration_minutes')
        .eq('attendance_log_id', logId)
        .order('start_time', ascending: true);
    return (rows as List)
        .map((r) => BreakSession.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Team attendance for the current NPT month, aggregated per employee.
  /// Pass [scopeUserIds] to limit to a manager's team (web useTeamAttendance:
  /// VP/Admin org-wide, every other manager .in(user_id, team)).
  Future<List<TeamMemberAttendance>> teamAttendance({List<String>? scopeUserIds}) async {
    if (scopeUserIds != null && scopeUserIds.isEmpty) return const [];
    var query = supabase
        .from('attendance_logs')
        .select(
          'user_id, clock_in, clock_out, total_break_minutes, total_pause_minutes',
        )
        .gte('clock_in', NptTime.nptMonthStartUtc().toIso8601String());
    if (scopeUserIds != null) {
      query = query.inFilter('user_id', scopeUserIds);
    }
    final rows = await query;

    final logs = (rows as List).cast<Map>();
    final nowUtc = DateTime.now().toUtc();

    final byUser = <String, ({double hours, Set<String> days})>{};
    for (final m in logs) {
      final uid = m['user_id'] as String?;
      if (uid == null) continue;
      final tmp = AttendanceLog.fromMap({
        'id': '_',
        'user_id': uid,
        'clock_in': m['clock_in'],
        'clock_out': m['clock_out'],
        'total_break_minutes': m['total_break_minutes'],
        'total_pause_minutes': m['total_pause_minutes'],
      });
      final entry = byUser[uid] ?? (hours: 0.0, days: <String>{});
      final newHours = entry.hours + tmp.netHours(nowUtc: nowUtc);
      final days = entry.days..add(NptTime.nptDateKey(tmp.clockIn));
      byUser[uid] = (hours: newHours, days: days);
    }

    if (byUser.isEmpty) return [];

    // Resolve names from profiles.
    final names = <String, String>{};
    final profs = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name')
        .inFilter('user_id', byUser.keys.toList());
    for (final p in profs as List) {
      final m = p as Map;
      names[m['user_id'] as String] =
          '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    }

    final result = byUser.entries
        .map((e) => TeamMemberAttendance(
              userId: e.key,
              name: names[e.key]?.isNotEmpty == true ? names[e.key]! : 'Unknown',
              totalHours: e.value.hours,
              daysWorked: e.value.days.length,
            ),)
        .toList()
      ..sort((a, b) => b.totalHours.compareTo(a.totalHours));
    return result;
  }

  /// Today's live team counts (RLS-scoped). Status is read directly off the
  /// logs that started today in NPT.
  Future<LiveAttendanceSummary> liveSummary() async {
    final rows = await supabase
        .from('attendance_logs')
        .select('status, clock_out, break_start, break_end, pause_start, pause_end, clock_in')
        .gte('clock_in', NptTime.nptTodayStartUtc().toIso8601String());
    var working = 0, onBreak = 0, paused = 0, out = 0;
    for (final r in rows as List) {
      final m = r as Map;
      final log = AttendanceLog.fromMap({
        'id': '_',
        'user_id': '_',
        'clock_in': m['clock_in'],
        'clock_out': m['clock_out'],
        'break_start': m['break_start'],
        'break_end': m['break_end'],
        'pause_start': m['pause_start'],
        'pause_end': m['pause_end'],
      });
      switch (log.clockStatus) {
        case ClockStatus.out:
          out++;
        case ClockStatus.onBreak:
          onBreak++;
        case ClockStatus.paused:
          paused++;
        case ClockStatus.active:
          working++;
      }
    }
    return LiveAttendanceSummary(
      working: working,
      onBreak: onBreak,
      paused: paused,
      out: out,
    );
  }

  // ── Adjustment requests (employee self-correction) ─────
  Future<void> submitAdjustment({
    required String logId,
    DateTime? originalClockIn,
    DateTime? originalClockOut,
    int? originalBreakMinutes,
    int? originalPauseMinutes,
    required DateTime proposedClockIn,
    required DateTime proposedClockOut,
    required int proposedBreakMinutes,
    required int proposedPauseMinutes,
    required String reason,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    await supabase.from('attendance_adjustment_requests').insert({
      'attendance_log_id': logId,
      'requested_by': uid,
      'proposed_clock_in': proposedClockIn.toUtc().toIso8601String(),
      'proposed_clock_out': proposedClockOut.toUtc().toIso8601String(),
      'proposed_break_minutes': proposedBreakMinutes,
      'proposed_pause_minutes': proposedPauseMinutes,
      'reason': reason,
      'status': 'pending',
      if (originalClockIn != null)
        'original_clock_in': originalClockIn.toUtc().toIso8601String(),
      if (originalClockOut != null)
        'original_clock_out': originalClockOut.toUtc().toIso8601String(),
      if (originalBreakMinutes != null)
        'original_break_minutes': originalBreakMinutes,
      if (originalPauseMinutes != null)
        'original_pause_minutes': originalPauseMinutes,
    });
    await _notifyManagers(uid);
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
      final userIds = (profs as List)
          .map((r) => (r as Map)['user_id'] as String?)
          .whereType<String>()
          .toSet();
      for (final mUid in userIds) {
        await supabase.rpc('create_notification', params: {
          'p_user_id': mUid,
          'p_title': '🕒 Attendance Adjustment Request',
          'p_message': 'A team member requested an attendance correction.',
          'p_type': 'attendance',
          'p_link': '/approvals',
        },);
      }
    } catch (_) {
      // Best-effort; never block the request on notification failure.
    }
  }

  /// Team adjustment requests visible to a manager/admin (RLS-scoped),
  /// newest first, with requester names resolved.
  Future<List<AdjustmentRequest>> teamAdjustments() async {
    final uid = supabase.auth.currentUser?.id;
    final rows = await supabase
        .from('attendance_adjustment_requests')
        .select(
          'id, attendance_log_id, requested_by, status, reason, '
          'proposed_clock_in, proposed_clock_out, proposed_break_minutes, '
          'proposed_pause_minutes, original_clock_in, original_clock_out, '
          'original_break_minutes, original_pause_minutes, reviewer_comment, '
          'override_status, created_at',
        )
        .neq('requested_by', uid as Object)
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => AdjustmentRequest.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) return list;

    final ids =
        list.map((r) => r.requestedBy).whereType<String>().toSet().toList();
    final names = <String, String>{};
    if (ids.isNotEmpty) {
      final profs = await supabase
          .from('profiles')
          .select('user_id, first_name, last_name')
          .inFilter('user_id', ids);
      for (final p in profs as List) {
        final m = p as Map;
        names[m['user_id'] as String] =
            '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      }
    }
    return list
        .map((r) => r.withRequester(names[r.requestedBy] ?? 'Employee'))
        .toList();
  }

  /// Manager review (approve/reject). A DB trigger applies an approved
  /// adjustment to the attendance log.
  Future<void> reviewAdjustment(
    String id, {
    required bool approved,
    String? comment,
  }) async {
    await supabase.from('attendance_adjustment_requests').update({
      'status': approved ? 'approved' : 'rejected',
      'reviewer_id': supabase.auth.currentUser!.id,
      'reviewer_comment': comment,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// VP/Admin override of a prior review.
  Future<void> overrideAdjustment(
    String id, {
    required bool approved,
    String? comment,
  }) async {
    await supabase.from('attendance_adjustment_requests').update({
      'status': approved ? 'approved' : 'rejected',
      'override_status': approved ? 'approved' : 'rejected',
      'override_by': supabase.auth.currentUser!.id,
      'override_comment': comment,
      'override_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<List<AdjustmentRequest>> myAdjustmentRequests() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await supabase
        .from('attendance_adjustment_requests')
        .select(
          'id, attendance_log_id, status, reason, proposed_clock_in, '
          'proposed_clock_out, proposed_break_minutes, proposed_pause_minutes, '
          'reviewer_comment, override_status, created_at',
        )
        .eq('requested_by', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => AdjustmentRequest.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }
}
