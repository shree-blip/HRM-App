/// Clock state derived from an attendance log's fields (matches the web app):
///   paused  -> pause_start set, pause_end null
///   break   -> break_start set, break_end null
///   active  -> open log, not paused/break
///   out     -> no open log
enum ClockStatus { out, active, onBreak, paused }

/// A row from `attendance_logs`.
class AttendanceLog {
  AttendanceLog({
    required this.id,
    required this.userId,
    this.employeeId,
    required this.clockIn,
    this.clockOut,
    this.breakStart,
    this.breakEnd,
    this.totalBreakMinutes = 0,
    this.pauseStart,
    this.pauseEnd,
    this.totalPauseMinutes = 0,
    this.status,
    this.workMode,
    this.clockType,
    this.locationName,
    this.isEdited = false,
  });

  final String id;
  final String userId;
  final String? employeeId;
  final DateTime clockIn;
  final DateTime? clockOut;
  final DateTime? breakStart;
  final DateTime? breakEnd;
  final int totalBreakMinutes;
  final DateTime? pauseStart;
  final DateTime? pauseEnd;
  final int totalPauseMinutes;
  final String? status;
  final String? workMode; // wfo | wfh
  final String? clockType; // payroll | billable
  final String? locationName;
  final bool isEdited;

  ClockStatus get clockStatus {
    if (clockOut != null) return ClockStatus.out;
    if (pauseStart != null && pauseEnd == null) return ClockStatus.paused;
    if (breakStart != null && breakEnd == null) return ClockStatus.onBreak;
    return ClockStatus.active;
  }

  bool get isOpen => clockOut == null;

  /// Net worked time: (end - clock_in) - breaks - pauses, accounting for an
  /// in-progress break/pause when [nowUtc] is supplied (live).
  Duration netElapsed(DateTime nowUtc) {
    final end = clockOut ?? nowUtc;
    var ms = end.difference(clockIn).inMilliseconds;
    ms -= (totalBreakMinutes + totalPauseMinutes) * 60000;
    if (clockOut == null) {
      if (breakStart != null && breakEnd == null) {
        ms -= nowUtc.difference(breakStart!).inMilliseconds;
      }
      if (pauseStart != null && pauseEnd == null) {
        ms -= nowUtc.difference(pauseStart!).inMilliseconds;
      }
    }
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  double netHours({DateTime? nowUtc}) =>
      netElapsed(nowUtc ?? DateTime.now().toUtc()).inMinutes / 60.0;

  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String)?.toUtc();

  factory AttendanceLog.fromMap(Map<String, dynamic> m) => AttendanceLog(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        employeeId: m['employee_id'] as String?,
        clockIn: _dt(m['clock_in'])!,
        clockOut: _dt(m['clock_out']),
        breakStart: _dt(m['break_start']),
        breakEnd: _dt(m['break_end']),
        totalBreakMinutes: ((m['total_break_minutes'] ?? 0) as num).toInt(),
        pauseStart: _dt(m['pause_start']),
        pauseEnd: _dt(m['pause_end']),
        totalPauseMinutes: ((m['total_pause_minutes'] ?? 0) as num).toInt(),
        status: m['status'] as String?,
        workMode: m['work_mode'] as String?,
        clockType: m['clock_type'] as String?,
        locationName: m['location_name'] as String?,
        isEdited: m['is_edited'] == true,
      );
}

/// A row from `attendance_break_sessions`.
class BreakSession {
  BreakSession({
    required this.id,
    required this.sessionType, // break | pause
    required this.startTime,
    this.endTime,
    this.durationMinutes,
  });

  final String id;
  final String sessionType;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMinutes;

  bool get isBreak => sessionType == 'break';

  factory BreakSession.fromMap(Map<String, dynamic> m) => BreakSession(
        id: m['id'] as String,
        sessionType: (m['session_type'] ?? 'break') as String,
        startTime: DateTime.parse(m['start_time'] as String).toUtc(),
        endTime: m['end_time'] != null
            ? DateTime.parse(m['end_time'] as String).toUtc()
            : null,
        durationMinutes: (m['duration_minutes'] as num?)?.toInt(),
      );
}

/// Today / week / month net-hours summary for the current user.
class AttendanceStats {
  const AttendanceStats({
    this.today = 0,
    this.week = 0,
    this.month = 0,
  });
  final double today;
  final double week;
  final double month;
}

/// Aggregated attendance for one team member (manager/admin view).
class TeamMemberAttendance {
  const TeamMemberAttendance({
    required this.userId,
    required this.name,
    required this.totalHours,
    required this.daysWorked,
  });
  final String userId;
  final String name;
  final double totalHours;
  final int daysWorked;
}

/// Live "today" team counts for the dashboard real-time card.
class LiveAttendanceSummary {
  const LiveAttendanceSummary({
    this.working = 0,
    this.onBreak = 0,
    this.paused = 0,
    this.out = 0,
  });
  final int working;
  final int onBreak;
  final int paused;
  final int out;
  int get clockedIn => working + onBreak + paused;
}
