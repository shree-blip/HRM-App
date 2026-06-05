import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/attendance_time.dart';
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
  /// RLS scopes rows (VP/Admin: all; line managers: their reports).
  Future<List<TeamMemberAttendance>> teamAttendance() async {
    final rows = await supabase
        .from('attendance_logs')
        .select(
          'user_id, clock_in, clock_out, total_break_minutes, total_pause_minutes',
        )
        .gte('clock_in', NptTime.nptMonthStartUtc().toIso8601String());

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
}
