/// Report date-range presets (mirrors useTeamAttendance dateRangeType).
enum ReportRange { thisMonth, lastMonth, thisQuarter, thisYear, custom }

extension ReportRangeLabel on ReportRange {
  String get label => switch (this) {
        ReportRange.thisMonth => 'This Month',
        ReportRange.lastMonth => 'Last Month',
        ReportRange.thisQuarter => 'This Quarter',
        ReportRange.thisYear => 'This Year',
        ReportRange.custom => 'Custom',
      };
}

/// A resolved [start, end) window in UTC for querying attendance_logs.
class ReportWindow {
  const ReportWindow(this.startUtc, this.endUtc, this.label);
  final DateTime startUtc;
  final DateTime endUtc;
  final String label;

  /// Computes the window for a preset (or custom dates). Month/quarter/year
  /// boundaries are taken in local time then converted to UTC for the query.
  static ReportWindow resolve(
    ReportRange range, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    DateTime start, endExclusive;
    switch (range) {
      case ReportRange.thisMonth:
        start = DateTime(now.year, now.month, 1);
        endExclusive = DateTime(now.year, now.month + 1, 1);
      case ReportRange.lastMonth:
        start = DateTime(now.year, now.month - 1, 1);
        endExclusive = DateTime(now.year, now.month, 1);
      case ReportRange.thisQuarter:
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        start = DateTime(now.year, qStartMonth, 1);
        endExclusive = DateTime(now.year, qStartMonth + 3, 1);
      case ReportRange.thisYear:
        start = DateTime(now.year, 1, 1);
        endExclusive = DateTime(now.year + 1, 1, 1);
      case ReportRange.custom:
        start = customStart ?? DateTime(now.year, now.month, 1);
        endExclusive = (customEnd ?? now).add(const Duration(days: 1));
    }
    final label = range == ReportRange.custom
        ? '${_d(start)} → ${_d(endExclusive.subtract(const Duration(days: 1)))}'
        : range.label;
    return ReportWindow(start.toUtc(), endExclusive.toUtc(), label);
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Per-employee attendance summary row.
class EmployeeSummary {
  EmployeeSummary({
    required this.userId,
    required this.name,
    required this.email,
    this.totalHours = 0,
    this.daysWorked = 0,
    this.paidLeaveDays = 0,
    this.payrollLeaveDays = 0,
  });

  final String userId;
  final String name;
  final String email;
  double totalHours;
  int daysWorked; // distinct clocked days
  double paidLeaveDays;
  double payrollLeaveDays;

  /// Days worked including paid leave (matches the web "Days Worked" column).
  double get effectiveDaysWorked => daysWorked + paidLeaveDays;

  String? get deductionType {
    final paid = paidLeaveDays > 0;
    final payroll = payrollLeaveDays > 0;
    if (paid && payroll) return 'Paid Leave | Payroll';
    if (paid) return 'Paid Leave';
    if (payroll) return 'Payroll';
    return null;
  }
}

/// One daily attendance record (employee-wise daily report).
class DailyRecord {
  const DailyRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.dateKey,
    required this.clockIn,
    this.clockOut,
    this.breakMinutes = 0,
    this.pauseMinutes = 0,
    this.netHours = 0,
    this.isEdited = false,
  });

  final String id; // attendance_logs id (needed for edit)
  final String userId;
  final String name;
  final String dateKey; // YYYY-MM-DD (NPT)
  final DateTime clockIn;
  final DateTime? clockOut;
  final int breakMinutes;
  final int pauseMinutes;
  final double netHours;
  final bool isEdited;

  /// Status band per the web (Complete 7.5–8.5h, Overtime ≥8.5, Short <7.5).
  String get status {
    if (clockOut == null) return 'In Progress';
    if (netHours >= 8.5) return 'Overtime';
    if (netHours >= 7.5) return 'Complete';
    return 'Short';
  }
}

/// The full report payload for a window.
class ReportData {
  const ReportData({
    required this.summaries,
    required this.daily,
    required this.workingDays,
  });
  final List<EmployeeSummary> summaries;
  final List<DailyRecord> daily;
  final int workingDays; // weekdays minus holidays in the window

  double get targetHours => workingDays * 8.0;
}
