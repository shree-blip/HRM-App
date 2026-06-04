import '../../../core/supabase/supabase_client.dart';

/// ── Models ───────────────────────────────────────────────

class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.isPinned,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String content;
  final String type;
  final bool isPinned;
  final DateTime? createdAt;

  factory AnnouncementItem.fromMap(Map<String, dynamic> m) => AnnouncementItem(
        id: m['id'] as String,
        title: (m['title'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        type: (m['type'] ?? 'general') as String,
        isPinned: m['is_pinned'] == true,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
      );
}

class LeaveBalanceItem {
  const LeaveBalanceItem({
    required this.leaveType,
    required this.totalDays,
    required this.usedDays,
  });

  final String leaveType;
  final num totalDays;
  final num usedDays;

  num get remaining => totalDays - usedDays;

  factory LeaveBalanceItem.fromMap(Map<String, dynamic> m) => LeaveBalanceItem(
        leaveType: (m['leave_type'] ?? '') as String,
        totalDays: (m['total_days'] ?? 0) as num,
        usedDays: (m['used_days'] ?? 0) as num,
      );
}

/// Aggregated numbers for the dashboard stat cards.
class DashboardSummary {
  const DashboardSummary({
    required this.employeeCount,
    required this.monthlyHours,
    required this.pendingTasks,
    required this.tasksDueToday,
    required this.pendingLeaves,
    required this.onLeaveTodayNames,
  });

  final int employeeCount;
  final double monthlyHours;
  final int pendingTasks;
  final int tasksDueToday;
  final int pendingLeaves;
  final List<String> onLeaveTodayNames;
}

/// ── Repository ───────────────────────────────────────────
///
/// All reads go through Supabase with the user's session, so RLS scopes the
/// rows exactly like the web app. No schema changes; read-only.
class DashboardRepository {
  /// "Today" in company timezone (Asia/Kathmandu, UTC+5:45) — matches the
  /// React dashboard which keys "today" off Nepal time for all viewers.
  static DateTime _nowNpt() => DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 45),
      );

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<int> employeeCount() async {
    final rows = await supabase.from('employees').select('id');
    return (rows as List).length;
  }

  /// Sum of net worked hours this month for [userId], using the business
  /// formula: (clock_out - clock_in) - break - pause.
  Future<double> monthlyHours(String userId) async {
    final npt = _nowNpt();
    final monthStartUtc = DateTime.utc(npt.year, npt.month, 1)
        .subtract(const Duration(hours: 5, minutes: 45));
    final rows = await supabase
        .from('attendance_logs')
        .select('clock_in, clock_out, total_break_minutes, total_pause_minutes')
        .eq('user_id', userId)
        .gte('clock_in', monthStartUtc.toIso8601String())
        .not('clock_out', 'is', null);

    var totalMinutes = 0.0;
    for (final row in rows as List) {
      final m = row as Map;
      final ci = DateTime.tryParse(m['clock_in'] as String? ?? '');
      final co = DateTime.tryParse(m['clock_out'] as String? ?? '');
      if (ci == null || co == null) continue;
      final gross = co.difference(ci).inMinutes.toDouble();
      final brk = ((m['total_break_minutes'] ?? 0) as num).toDouble();
      final pause = ((m['total_pause_minutes'] ?? 0) as num).toDouble();
      final net = gross - brk - pause;
      if (net > 0) totalMinutes += net;
    }
    return totalMinutes / 60.0;
  }

  Future<({int pending, int dueToday})> taskStats() async {
    final rows =
        await supabase.from('tasks').select('status, due_date');
    final today = _dateKey(_nowNpt());
    var pending = 0;
    var dueToday = 0;
    for (final row in rows as List) {
      final m = row as Map;
      final status = m['status'] as String?;
      if (status == 'done') continue;
      pending++;
      if (m['due_date'] == today) dueToday++;
    }
    return (pending: pending, dueToday: dueToday);
  }

  /// Pending leaves visible to the user (own for employees, team+own for
  /// managers — RLS enforces the scope), plus who is on leave today.
  Future<({int pending, List<String> onLeaveTodayNames})> leaveStats() async {
    final today = _dateKey(_nowNpt());

    final pendingRows = await supabase
        .from('leave_requests')
        .select('id')
        .eq('status', 'pending');

    final onLeaveRows = await supabase
        .from('leave_requests')
        .select('user_id, start_date, end_date')
        .eq('status', 'approved')
        .lte('start_date', today)
        .gte('end_date', today);

    final userIds = (onLeaveRows as List)
        .map((r) => (r as Map)['user_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final names = <String>[];
    if (userIds.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('user_id, first_name')
          .inFilter('user_id', userIds);
      for (final p in profiles as List) {
        final m = p as Map;
        final fn = (m['first_name'] ?? '') as String;
        if (fn.isNotEmpty) names.add(fn);
      }
    }

    return (pending: (pendingRows as List).length, onLeaveTodayNames: names);
  }

  Future<List<AnnouncementItem>> announcements({int limit = 5}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await supabase
        .from('announcements')
        .select('id, title, content, type, is_pinned, created_at, expires_at, is_active')
        .eq('is_active', true)
        .or('expires_at.is.null,expires_at.gt.$nowIso')
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => AnnouncementItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<LeaveBalanceItem>> leaveBalances(String userId) async {
    final year = _nowNpt().year;
    final rows = await supabase
        .from('leave_balances')
        .select('leave_type, total_days, used_days')
        .eq('user_id', userId)
        .eq('year', year);
    return (rows as List)
        .map((r) => LeaveBalanceItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Builds the stat-card summary in parallel.
  Future<DashboardSummary> summary({
    required String userId,
    required bool isManager,
  }) async {
    final results = await Future.wait([
      isManager ? employeeCount() : Future.value(0),
      monthlyHours(userId),
      taskStats(),
      leaveStats(),
    ]);

    final tasks = results[2] as ({int pending, int dueToday});
    final leave = results[3] as ({int pending, List<String> onLeaveTodayNames});

    return DashboardSummary(
      employeeCount: results[0] as int,
      monthlyHours: results[1] as double,
      pendingTasks: tasks.pending,
      tasksDueToday: tasks.dueToday,
      pendingLeaves: leave.pending,
      onLeaveTodayNames: leave.onLeaveTodayNames,
    );
  }
}
