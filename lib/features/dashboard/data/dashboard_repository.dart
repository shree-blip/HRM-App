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

  // ── TasksWidget ────────────────────────────────────────
  Future<List<TaskItem>> recentTasks({int limit = 4}) async {
    final rows = await supabase
        .from('tasks')
        .select('id, title, client_name, priority, status, due_date, created_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => TaskItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  // ── LeaveWidget ────────────────────────────────────────
  Future<List<LeaveItem>> recentLeave({int limit = 5}) async {
    final rows = await supabase
        .from('leave_requests')
        .select(
          'id, user_id, leave_type, start_date, end_date, days, status, is_half_day, created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    final list =
        (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();

    final ids = list
        .map((m) => m['user_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final nameMap = <String, String>{};
    if (ids.isNotEmpty) {
      final profs = await supabase
          .from('profiles')
          .select('user_id, first_name, last_name')
          .inFilter('user_id', ids);
      for (final p in profs as List) {
        final m = p as Map;
        nameMap[m['user_id'] as String] =
            '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      }
    }
    return list
        .map((m) => LeaveItem.fromMap(m, nameMap[m['user_id']] ?? ''))
        .toList();
  }

  // ── DailyTimelineWidget ────────────────────────────────
  Future<List<MilestoneItem>> milestones({
    int withinDays = 14,
    int limit = 3,
  }) async {
    final rows = await supabase
        .from('profiles')
        .select('first_name, last_name, date_of_birth, joining_date, status')
        .neq('status', 'inactive');
    final npt = _nowNpt();
    final today = DateTime(npt.year, npt.month, npt.day);
    final items = <MilestoneItem>[];

    for (final r in rows as List) {
      final m = r as Map;
      final name =
          '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      void addIfSoon(String? dateStr, String type) {
        if (dateStr == null) return;
        final d = DateTime.tryParse(dateStr);
        if (d == null) return;
        var next = DateTime(today.year, d.month, d.day);
        if (next.isBefore(today)) next = DateTime(today.year + 1, d.month, d.day);
        final days = next.difference(today).inDays;
        if (days >= 0 && days <= withinDays) {
          items.add(MilestoneItem(
            name: name,
            type: type,
            date: next,
            daysUntil: days,
            years: type == 'anniversary' ? next.year - d.year : null,
          ),);
        }
      }

      addIfSoon(m['date_of_birth'] as String?, 'birthday');
      addIfSoon(m['joining_date'] as String?, 'anniversary');
    }
    items.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
    return items.take(limit).toList();
  }

  Future<List<CalendarItem>> upcomingDeadlines({int limit = 3}) async {
    final today = _dateKey(_nowNpt());
    final rows = await supabase
        .from('calendar_events')
        .select('title, description, event_date')
        .eq('is_active', true)
        .eq('event_type', 'deadline')
        .gte('event_date', today)
        .order('event_date', ascending: true)
        .limit(limit);
    return (rows as List)
        .map((r) => CalendarItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<HolidayItem>> upcomingHolidays({int limit = 3}) async {
    final rows = await supabase
        .from('company_holidays')
        .select('name, date, is_recurring');
    final npt = _nowNpt();
    final today = DateTime(npt.year, npt.month, npt.day);
    final items = <HolidayItem>[];
    for (final r in rows as List) {
      final m = r as Map;
      final ds = m['date'] as String?;
      if (ds == null) continue;
      final d = DateTime.tryParse(ds);
      if (d == null) continue;
      DateTime occ;
      if (m['is_recurring'] == true) {
        occ = DateTime(today.year, d.month, d.day);
        if (occ.isBefore(today)) occ = DateTime(today.year + 1, d.month, d.day);
      } else {
        occ = DateTime(d.year, d.month, d.day);
      }
      final days = occ.difference(today).inDays;
      if (days >= 0) {
        items.add(HolidayItem(
          name: (m['name'] ?? '') as String,
          date: occ,
          daysUntil: days,
        ),);
      }
    }
    items.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
    return items.take(limit).toList();
  }

  // ── PersonalReportsWidget (employee) ───────────────────
  Future<PersonalReport> personalReport(String userId) async {
    final hours = await monthlyHours(userId);
    final npt = _nowNpt();
    final daysInMonth = DateTime(npt.year, npt.month + 1, 0).day;
    var workingDays = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      if (DateTime(npt.year, npt.month, day).weekday < 6) workingDays++;
    }
    final target = workingDays * 8.0;

    final balances = await leaveBalances(userId);
    LeaveBalanceItem? annual;
    for (final b in balances) {
      if (b.leaveType.toLowerCase().contains('annual')) {
        annual = b;
        break;
      }
    }

    final managers = <String>[];
    var teammateCount = 0;
    try {
      final empId =
          await supabase.rpc('get_employee_id_for_user', params: {'_user_id': userId});
      if (empId is String) {
        final tm = await supabase
            .from('team_members')
            .select('manager_employee_id')
            .eq('member_employee_id', empId);
        final mgrIds = (tm as List)
            .map((r) => (r as Map)['manager_employee_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList();
        if (mgrIds.isNotEmpty) {
          final emps = await supabase
              .from('employees')
              .select('first_name, last_name')
              .inFilter('id', mgrIds);
          for (final e in emps as List) {
            final m = e as Map;
            final n = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
            if (n.isNotEmpty) managers.add(n);
          }
          final mates = await supabase
              .from('team_members')
              .select('member_employee_id')
              .inFilter('manager_employee_id', mgrIds);
          final mateIds = (mates as List)
              .map((r) => (r as Map)['member_employee_id'] as String?)
              .whereType<String>()
              .toSet()
            ..remove(empId);
          teammateCount = mateIds.length;
        }
      }
    } catch (_) {
      // Best-effort hierarchy; degrade gracefully.
    }

    return PersonalReport(
      monthlyHours: hours,
      targetHours: target,
      annual: annual,
      managerNames: managers,
      teammateCount: teammateCount,
    );
  }

  // ── TeamReportsWidget (manager/admin) ──────────────────
  Future<TeamReport> teamReport() async {
    final results = await Future.wait([
      employeeCount(),
      _clockedInToday(),
      leaveStats(),
      _taskCompletion(),
    ]);
    final leave = results[2] as ({int pending, List<String> onLeaveTodayNames});
    final tc = results[3] as ({int total, int done});
    return TeamReport(
      teamSize: results[0] as int,
      clockedInToday: results[1] as int,
      pendingLeaves: leave.pending,
      totalTasks: tc.total,
      doneTasks: tc.done,
    );
  }

  Future<int> _clockedInToday() async {
    final npt = _nowNpt();
    final dayStartUtc = DateTime.utc(npt.year, npt.month, npt.day)
        .subtract(const Duration(hours: 5, minutes: 45));
    final rows = await supabase
        .from('attendance_logs')
        .select('id')
        .gte('clock_in', dayStartUtc.toIso8601String())
        .isFilter('clock_out', null);
    return (rows as List).length;
  }

  Future<({int total, int done})> _taskCompletion() async {
    final rows = await supabase.from('tasks').select('status');
    var total = 0;
    var done = 0;
    for (final r in rows as List) {
      total++;
      if ((r as Map)['status'] == 'done') done++;
    }
    return (total: total, done: done);
  }
}

/// ── Additional models for the new dashboard widgets ──────

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.clientName,
    required this.priority,
    required this.status,
    required this.dueDate,
  });

  final String id;
  final String title;
  final String? clientName;
  final String? priority;
  final String? status;
  final String? dueDate;

  bool get isDone => status == 'done';

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: (m['title'] ?? '') as String,
        clientName: m['client_name'] as String?,
        priority: m['priority'] as String?,
        status: m['status'] as String?,
        dueDate: m['due_date'] as String?,
      );
}

class LeaveItem {
  const LeaveItem({
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.status,
    required this.employeeName,
    required this.isHalfDay,
  });

  final String leaveType;
  final String startDate;
  final String endDate;
  final num days;
  final String status;
  final String employeeName;
  final bool isHalfDay;

  factory LeaveItem.fromMap(Map<String, dynamic> m, String name) => LeaveItem(
        leaveType: (m['leave_type'] ?? '') as String,
        startDate: (m['start_date'] ?? '') as String,
        endDate: (m['end_date'] ?? '') as String,
        days: (m['days'] ?? 0) as num,
        status: (m['status'] ?? '') as String,
        employeeName: name,
        isHalfDay: m['is_half_day'] == true,
      );
}

class MilestoneItem {
  const MilestoneItem({
    required this.name,
    required this.type, // birthday | anniversary
    required this.date,
    required this.daysUntil,
    this.years,
  });

  final String name;
  final String type;
  final DateTime date;
  final int daysUntil;
  final int? years;
}

class CalendarItem {
  const CalendarItem({
    required this.title,
    required this.description,
    required this.eventDate,
  });

  final String title;
  final String? description;
  final String eventDate;

  factory CalendarItem.fromMap(Map<String, dynamic> m) => CalendarItem(
        title: (m['title'] ?? '') as String,
        description: m['description'] as String?,
        eventDate: (m['event_date'] ?? '') as String,
      );
}

class HolidayItem {
  const HolidayItem({
    required this.name,
    required this.date,
    required this.daysUntil,
  });

  final String name;
  final DateTime date;
  final int daysUntil;
}

class PersonalReport {
  const PersonalReport({
    required this.monthlyHours,
    required this.targetHours,
    required this.annual,
    required this.managerNames,
    required this.teammateCount,
  });

  final double monthlyHours;
  final double targetHours;
  final LeaveBalanceItem? annual;
  final List<String> managerNames;
  final int teammateCount;

  double get progress =>
      targetHours <= 0 ? 0 : (monthlyHours / targetHours).clamp(0, 1).toDouble();
}

class TeamReport {
  const TeamReport({
    required this.teamSize,
    required this.clockedInToday,
    required this.pendingLeaves,
    required this.totalTasks,
    required this.doneTasks,
  });

  final int teamSize;
  final int clockedInToday;
  final int pendingLeaves;
  final int totalTasks;
  final int doneTasks;

  int get taskCompletionPct =>
      totalTasks == 0 ? 0 : ((doneTasks / totalTasks) * 100).round();
}
