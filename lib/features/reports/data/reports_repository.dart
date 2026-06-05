import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/attendance_time.dart';
import 'reports_models.dart';

/// Attendance Summary / Reports data access. Reads attendance_logs (RLS scopes
/// to team for managers, org-wide for VP/Admin) + approved leave, aggregates
/// per employee, and computes working days. No schema changes.
class ReportsRepository {
  Future<ReportData> fetch(ReportWindow w) async {
    // 1. Attendance logs in the window.
    final logRows = await supabase
        .from('attendance_logs')
        .select(
          'user_id, clock_in, clock_out, total_break_minutes, '
          'total_pause_minutes, is_edited',
        )
        .gte('clock_in', w.startUtc.toIso8601String())
        .lt('clock_in', w.endUtc.toIso8601String())
        .order('clock_in', ascending: false);
    final logs = (logRows as List).cast<Map>();

    // 2. Resolve names/emails for everyone referenced (logs + leave).
    final userIds = <String>{
      for (final l in logs) if (l['user_id'] != null) l['user_id'] as String,
    };

    // 3. Approved leave overlapping the window.
    final startKey = NptTime.nptDateKey(w.startUtc);
    final endKeyIncl =
        NptTime.nptDateKey(w.endUtc.subtract(const Duration(days: 1)));
    final leaveRows = await supabase
        .from('leave_requests')
        .select('user_id, start_date, end_date, days, reason, is_half_day')
        .eq('status', 'approved')
        .lte('start_date', endKeyIncl)
        .gte('end_date', startKey);
    final leaves = (leaveRows as List).cast<Map>();
    for (final lv in leaves) {
      if (lv['user_id'] != null) userIds.add(lv['user_id'] as String);
    }

    final names = <String, ({String name, String email})>{};
    if (userIds.isNotEmpty) {
      final profs = await supabase
          .from('profiles')
          .select('user_id, first_name, last_name, email')
          .inFilter('user_id', userIds.toList());
      for (final p in profs as List) {
        final m = p as Map;
        names[m['user_id'] as String] = (
          name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
          email: (m['email'] ?? '') as String,
        );
      }
    }

    // 4. Daily records + per-employee aggregation.
    final daily = <DailyRecord>[];
    final summaries = <String, EmployeeSummary>{};
    final daysByUser = <String, Set<String>>{};
    final nowUtc = DateTime.now().toUtc();

    for (final l in logs) {
      final uid = l['user_id'] as String?;
      if (uid == null) continue;
      final ci = DateTime.tryParse(l['clock_in'] as String? ?? '')?.toUtc();
      if (ci == null) continue;
      final co = l['clock_out'] != null
          ? DateTime.tryParse(l['clock_out'] as String)?.toUtc()
          : null;
      final brk = ((l['total_break_minutes'] ?? 0) as num).toInt();
      final pause = ((l['total_pause_minutes'] ?? 0) as num).toInt();
      final end = co ?? nowUtc;
      var net = (end.difference(ci).inMinutes - brk - pause) / 60.0;
      if (net < 0) net = 0;
      final dateKey = NptTime.nptDateKey(ci);
      final info = names[uid] ?? (name: 'Employee', email: '');

      daily.add(DailyRecord(
        userId: uid,
        name: info.name,
        dateKey: dateKey,
        clockIn: ci,
        clockOut: co,
        breakMinutes: brk,
        pauseMinutes: pause,
        netHours: net,
        isEdited: l['is_edited'] == true,
      ),);

      final s = summaries.putIfAbsent(
          uid, () => EmployeeSummary(userId: uid, name: info.name, email: info.email),);
      (daysByUser[uid] ??= <String>{}).add(dateKey);
      if (co != null) s.totalHours += net;
    }
    for (final e in summaries.entries) {
      e.value
        ..daysWorked = (daysByUser[e.key] ?? const {}).length
        ..totalHours = (e.value.totalHours * 10).round() / 10;
    }

    // 5. Leave -> paid / payroll day counts (weekdays only).
    for (final lv in leaves) {
      final uid = lv['user_id'] as String?;
      if (uid == null) continue;
      final reason = (lv['reason'] ?? '') as String;
      final isPaid = RegExp(r'^\s*\[Paid Leave\]', caseSensitive: false).hasMatch(reason);
      final isPayroll = RegExp(r'^\s*\[Payroll\]', caseSensitive: false).hasMatch(reason);
      // Default (no prefix) is treated as a payroll deduction, per the web.
      final bucket = isPaid ? 'paid' : (isPayroll ? 'payroll' : 'payroll');

      final ls = DateTime.tryParse(lv['start_date'] as String? ?? '');
      final le = DateTime.tryParse(lv['end_date'] as String? ?? '');
      if (ls == null || le == null) continue;
      double days;
      if (lv['is_half_day'] == true) {
        days = 0.5;
      } else {
        days = _weekdaysBetween(
          _maxDate(ls, _parseKey(startKey)),
          _minDate(le, _parseKey(endKeyIncl)),
        ).toDouble();
      }
      if (days <= 0) continue;
      final info = names[uid] ?? (name: 'Employee', email: '');
      final s = summaries.putIfAbsent(
          uid, () => EmployeeSummary(userId: uid, name: info.name, email: info.email),);
      if (bucket == 'paid') {
        s.paidLeaveDays += days;
      } else {
        s.payrollLeaveDays += days;
      }
    }

    // 6. Working days = weekdays in window minus holidays.
    final workingDays = await _workingDays(startKey, endKeyIncl);

    final summaryList = summaries.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ReportData(
      summaries: summaryList,
      daily: daily,
      workingDays: workingDays,
    );
  }

  Future<int> _workingDays(String startKey, String endKeyIncl) async {
    final start = _parseKey(startKey);
    final end = _parseKey(endKeyIncl);
    // Holiday date keys in range (handles recurring by mapping month/day to
    // each spanned year).
    final holidays = <String>{};
    try {
      final rows = await supabase
          .from('company_holidays')
          .select('date, is_recurring');
      for (final r in rows as List) {
        final m = r as Map;
        final d = DateTime.tryParse(m['date'] as String? ?? '');
        if (d == null) continue;
        if (m['is_recurring'] == true) {
          for (var y = start.year; y <= end.year; y++) {
            holidays.add(_key(DateTime(y, d.month, d.day)));
          }
        } else {
          holidays.add(_key(d));
        }
      }
    } catch (_) {}

    var count = 0;
    var d = start;
    while (!d.isAfter(end)) {
      final weekday = d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;
      if (weekday && !holidays.contains(_key(d))) count++;
      d = d.add(const Duration(days: 1));
    }
    return count;
  }

  static int _weekdaysBetween(DateTime from, DateTime to) {
    if (to.isBefore(from)) return 0;
    var count = 0;
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) count++;
      d = d.add(const Duration(days: 1));
    }
    return count;
  }

  static DateTime _parseKey(String k) => DateTime.parse(k);
  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  // ── CSV builders ───────────────────────────────────────
  String summaryCsv(ReportData data) {
    final rows = <String>[
      'Employee,Email,Total Working Days,Days Worked,Total Hours,Paid Leave Days,Payroll Leave Days,Deduction Type',
    ];
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    for (final s in data.summaries) {
      rows.add([
        q(s.name),
        q(s.email),
        '${data.workingDays}',
        _n(s.effectiveDaysWorked),
        _n(s.totalHours),
        _n(s.paidLeaveDays),
        _n(s.payrollLeaveDays),
        q(s.deductionType ?? '-'),
      ].join(','),);
    }
    return '\u{FEFF}${rows.join('\n')}';
  }

  String dailyCsv(List<DailyRecord> records) {
    final rows = <String>[
      'Date,Employee,Clock In,Clock Out,Break (min),Pause (min),Net Hours,Status',
    ];
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    for (final r in records) {
      rows.add([
        q(r.dateKey),
        q(r.name),
        q(NptTime.formatTime(r.clockIn)),
        q(r.clockOut != null ? NptTime.formatTime(r.clockOut!) : '-'),
        '${r.breakMinutes}',
        '${r.pauseMinutes}',
        _n(r.netHours),
        q(r.status),
      ].join(','),);
    }
    return '\u{FEFF}${rows.join('\n')}';
  }

  static String _n(num v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
}
