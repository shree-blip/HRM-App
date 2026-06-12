import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/attendance_time.dart';

/// Status codes mirror the web Live Attendance widget.
/// Employee current state: IN | OUT | BRS | PAUSE | — (no log).
/// Event types also include BRE (break end / resumed) and CONT (pause end).
class LiveEmployee {
  const LiveEmployee({
    required this.id,
    required this.name,
    required this.department,
    required this.status,
    required this.lastAction,
    required this.avatarUrl,
    required this.workMode,
  });

  final String id;
  final String name;
  final String? department;
  final String status; // IN | OUT | BRS | PAUSE | —
  final DateTime? lastAction;
  final String? avatarUrl;
  final String? workMode; // wfo | wfh | null
}

class LiveEvent {
  const LiveEvent({
    required this.id,
    required this.name,
    required this.type,
    required this.time,
    this.department,
  });

  final String id;
  final String name;
  final String type; // IN | OUT | BRS | BRE | PAUSE | CONT
  final DateTime time;
  final String? department;
}

class LiveData {
  const LiveData({
    required this.employees,
    required this.events,
    required this.total,
    required this.working,
    required this.onBreak,
    required this.paused,
    required this.out,
  });

  final List<LiveEmployee> employees;
  final List<LiveEvent> events;
  final int total;
  final int working;
  final int onBreak;
  final int paused;
  final int out;

  static const empty = LiveData(
    employees: [],
    events: [],
    total: 0,
    working: 0,
    onBreak: 0,
    paused: 0,
    out: 0,
  );
}

/// Data access for the Live Attendance widget — mirrors the web
/// RealTimeAttendanceWidget's queries and status/event derivation.
/// RLS scopes which rows the user sees. No schema changes.
class LiveAttendanceRepository {
  static DateTime _utcDayStart([DateTime? now]) {
    final n = (now ?? DateTime.now()).toUtc();
    return DateTime.utc(n.year, n.month, n.day);
  }

  static String _empStatus(Map l) {
    if (l['clock_out'] != null) return 'OUT';
    if (l['pause_start'] != null && l['pause_end'] == null) return 'PAUSE';
    if (l['break_start'] != null && l['break_end'] == null) return 'BRS';
    return 'IN';
  }

  static DateTime? _maxTime(Map l) {
    final candidates = [
      l['clock_out'], l['pause_end'], l['pause_start'],
      l['break_end'], l['break_start'], l['clock_in'],
    ].whereType<String>().map((s) => DateTime.tryParse(s)?.toUtc()).whereType<DateTime>();
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => b.isAfter(a) ? b : a);
  }

  /// Builds the full live snapshot for "today" (UTC day, matching the web app).
  Future<LiveData> liveData() async {
    final dayStart = _utcDayStart();
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dayStartIso = dayStart.toIso8601String();
    final dayEndIso = dayEnd.toIso8601String();

    final emps = await supabase
        .from('employees')
        .select(
          'id, first_name, last_name, department, profile_id, '
          'profiles:profile_id(user_id, avatar_url)',
        )
        .inFilter('status', ['active', 'probation']);

    final todayLogs = await supabase
        .from('attendance_logs')
        .select('*')
        .gte('clock_in', dayStartIso)
        .lt('clock_in', dayEndIso)
        .order('clock_in', ascending: false);

    final activeOld = await supabase
        .from('attendance_logs')
        .select('*')
        .lt('clock_in', dayStartIso)
        .isFilter('clock_out', null);

    final crossMidnight = await supabase
        .from('attendance_logs')
        .select('*')
        .lt('clock_in', dayStartIso)
        .gte('clock_out', dayStartIso)
        .lt('clock_out', dayEndIso);

    // Merge + dedupe logs by id.
    final logsById = <String, Map>{};
    for (final l in [...todayLogs as List, ...activeOld as List, ...crossMidnight as List]) {
      final m = l as Map;
      logsById.putIfAbsent(m['id'] as String, () => m);
    }
    final logs = logsById.values.toList();

    // user_id -> employee_id, and avatar paths per employee.
    final userToEmp = <String, String>{};
    final empRows = (emps as List).cast<Map>();
    final avatarPathByEmp = <String, String>{};
    for (final e in empRows) {
      final prof = e['profiles'] as Map?;
      final uid = prof?['user_id'] as String?;
      if (uid != null) userToEmp[uid] = e['id'] as String;
      final av = prof?['avatar_url'] as String?;
      if (av != null && av.isNotEmpty) avatarPathByEmp[e['id'] as String] = av;
    }

    // Latest log per employee (by employee_id, fallback user_id).
    final logByEmp = <String, Map>{};
    final logByUser = <String, Map>{};
    for (final l in logs) {
      final eid = l['employee_id'] as String?;
      final uid = l['user_id'] as String?;
      if (eid != null) logByEmp.putIfAbsent(eid, () => l);
      if (uid != null) logByUser.putIfAbsent(uid, () => l);
    }

    final signed = await _signAvatars(avatarPathByEmp);

    final employees = <LiveEmployee>[];
    for (final e in empRows) {
      final eid = e['id'] as String;
      final prof = e['profiles'] as Map?;
      final uid = prof?['user_id'] as String?;
      final log = logByEmp[eid] ?? (uid != null ? logByUser[uid] : null);
      employees.add(LiveEmployee(
        id: eid,
        name: '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
        department: e['department'] as String?,
        status: log != null ? _empStatus(log) : '—',
        lastAction: log != null ? _maxTime(log) : null,
        avatarUrl: signed[avatarPathByEmp[eid]],
        workMode: _normMode(log?['work_mode'] as String?),
      ),);
    }

    employees.sort((a, b) {
      if (a.lastAction == null && b.lastAction == null) return 0;
      if (a.lastAction == null) return 1;
      if (b.lastAction == null) return -1;
      return b.lastAction!.compareTo(a.lastAction!);
    });

    final working = employees.where((e) => e.status == 'IN').length;
    final onBreak = employees.where((e) => e.status == 'BRS').length;
    final paused = employees.where((e) => e.status == 'PAUSE').length;
    final out = employees.where((e) => e.status == 'OUT').length;

    final events = await _buildEvents(logs, empRows, userToEmp);

    return LiveData(
      employees: employees,
      events: events,
      total: employees.length,
      working: working,
      onBreak: onBreak,
      paused: paused,
      out: out,
    );
  }

  /// All activity events since [startUtc] (for the full-activity timeline's
  /// Week / Month ranges). RLS-scoped.
  Future<List<LiveEvent>> eventsSince(DateTime startUtc) async {
    final logs = await supabase
        .from('attendance_logs')
        .select('*')
        .gte('clock_in', startUtc.toIso8601String())
        .order('clock_in', ascending: false)
        .limit(20000);
    final emps = await supabase.from('employees').select(
          'id, first_name, last_name, department, profiles:profile_id(user_id)',
        );
    final empRows = (emps as List).cast<Map>();
    final userToEmp = <String, String>{};
    for (final e in empRows) {
      final uid = (e['profiles'] as Map?)?['user_id'] as String?;
      if (uid != null) userToEmp[uid] = e['id'] as String;
    }
    return _buildEvents((logs as List).cast<Map>(), empRows, userToEmp);
  }

  Future<List<LiveEvent>> _buildEvents(
    List<Map> logs,
    List<Map> empRows,
    Map<String, String> userToEmp,
  ) async {
    final nameByEmp = <String, ({String name, String? dept})>{};
    final empByUser = <String, ({String name, String? dept})>{};
    for (final e in empRows) {
      final entry = (
        name: '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.trim(),
        dept: e['department'] as String?,
      );
      nameByEmp[e['id'] as String] = entry;
      final uid = (e['profiles'] as Map?)?['user_id'] as String?;
      if (uid != null) empByUser[uid] = entry;
    }

    // Sessions for these logs (batched).
    final logIds = logs.map((l) => l['id'] as String).toList();
    final sessionsByLog = <String, List<Map>>{};
    for (var i = 0; i < logIds.length; i += 200) {
      final batch = logIds.sublist(i, (i + 200).clamp(0, logIds.length));
      if (batch.isEmpty) continue;
      final rows = await supabase
          .from('attendance_break_sessions')
          .select('attendance_log_id, session_type, start_time, end_time')
          .inFilter('attendance_log_id', batch)
          .order('start_time', ascending: true);
      for (final r in rows as List) {
        final m = r as Map;
        (sessionsByLog[m['attendance_log_id'] as String] ??= []).add(m);
      }
    }

    final events = <LiveEvent>[];
    DateTime? t(dynamic v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

    for (final log in logs) {
      final eid = log['employee_id'] as String?;
      final uid = log['user_id'] as String?;
      final info = (eid != null ? nameByEmp[eid] : null) ??
          (uid != null ? empByUser[uid] : null) ??
          (uid != null && userToEmp[uid] != null ? nameByEmp[userToEmp[uid]] : null);
      final name = info?.name ?? '';
      if (name.isEmpty) continue;
      final dept = info?.dept;
      final id = log['id'] as String;

      void add(String type, DateTime? time) {
        if (time == null) return;
        events.add(LiveEvent(
          id: '$id-$type-${time.millisecondsSinceEpoch}',
          name: name,
          type: type,
          time: time,
          department: dept,
        ),);
      }

      add('IN', t(log['clock_in']));
      final sessions = sessionsByLog[id] ?? const [];
      if (sessions.isNotEmpty) {
        for (final s in sessions) {
          if (s['session_type'] == 'break') {
            add('BRS', t(s['start_time']));
            add('BRE', t(s['end_time']));
          } else if (s['session_type'] == 'pause') {
            add('PAUSE', t(s['start_time']));
            add('CONT', t(s['end_time']));
          }
        }
      } else {
        add('BRS', t(log['break_start']));
        add('BRE', t(log['break_end']));
        add('PAUSE', t(log['pause_start']));
        add('CONT', t(log['pause_end']));
      }
      add('OUT', t(log['clock_out']));
    }

    events.sort((a, b) => b.time.compareTo(a.time));
    return events.take(200).toList();
  }

  /// Builds a CSV string of attendance for [timeframe] = today | week | month
  /// (RLS-scoped), mirroring the web export's core columns.
  Future<String> attendanceCsv(
    String timeframe, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final now = DateTime.now().toUtc();
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    DateTime start;
    DateTime end = dayStart.add(const Duration(days: 1));
    if (timeframe == 'custom' && customStart != null && customEnd != null) {
      start = DateTime.utc(customStart.year, customStart.month, customStart.day);
      end = DateTime.utc(customEnd.year, customEnd.month, customEnd.day)
          .add(const Duration(days: 1));
    } else if (timeframe == 'today') {
      start = dayStart;
    } else if (timeframe == 'week') {
      final wd = now.weekday; // Mon=1..Sun=7
      start = dayStart.subtract(Duration(days: wd - 1));
    } else {
      start = DateTime.utc(now.year, now.month, 1);
    }

    final logs = await supabase
        .from('attendance_logs')
        .select(
          'id, user_id, employee_id, clock_in, clock_out, '
          'total_break_minutes, total_pause_minutes, work_mode',
        )
        .gte('clock_in', start.toIso8601String())
        .lt('clock_in', end.toIso8601String())
        .order('clock_in', ascending: false)
        .limit(10000);

    final emps = await supabase
        .from('employees')
        .select('id, first_name, last_name, department, profiles:profile_id(user_id)');
    final nameByEmp = <String, ({String name, String? dept})>{};
    final empByUser = <String, ({String name, String? dept})>{};
    for (final e in emps as List) {
      final m = e as Map;
      final entry = (
        name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
        dept: m['department'] as String?,
      );
      nameByEmp[m['id'] as String] = entry;
      final uid = (m['profiles'] as Map?)?['user_id'] as String?;
      if (uid != null) empByUser[uid] = entry;
    }

    String fmtTime(dynamic v) {
      if (v is! String) return '-';
      final d = DateTime.tryParse(v)?.toUtc().add(NptTime.offset);
      if (d == null) return '-';
      var h = d.hour % 12;
      if (h == 0) h = 12;
      final ap = d.hour < 12 ? 'AM' : 'PM';
      return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
    }

    final rows = <String>[];
    rows.add(
      'Date,Employee,Department,Work Mode,Clock In,Clock Out,Break (min),Pause (min),Net Hours',
    );
    for (final l in logs as List) {
      final m = l as Map;
      final eid = m['employee_id'] as String?;
      final uid = m['user_id'] as String?;
      final info = (eid != null ? nameByEmp[eid] : null) ??
          (uid != null ? empByUser[uid] : null);
      final ci = DateTime.tryParse(m['clock_in'] as String)?.toUtc();
      final co = m['clock_out'] != null
          ? DateTime.tryParse(m['clock_out'] as String)?.toUtc()
          : null;
      final brk = ((m['total_break_minutes'] ?? 0) as num).toInt();
      final pause = ((m['total_pause_minutes'] ?? 0) as num).toInt();
      var net = 0.0;
      if (ci != null) {
        final endT = co ?? now;
        net = (endT.difference(ci).inMinutes - brk - pause) / 60.0;
        if (net < 0) net = 0;
      }
      final dateKey = ci != null ? NptTime.nptDateKey(ci) : '-';
      String q(String s) => '"${s.replaceAll('"', '""')}"';
      rows.add([
        q(dateKey),
        q(info?.name ?? 'Unknown'),
        q(info?.dept ?? '-'),
        q((m['work_mode'] as String?)?.toUpperCase() ?? '-'),
        q(fmtTime(m['clock_in'])),
        q(fmtTime(m['clock_out'])),
        '$brk',
        '$pause',
        q('${net.toStringAsFixed(2)}h'),
      ].join(','),);
    }
    return '﻿${rows.join('\n')}';
  }

  static String? _normMode(String? m) => (m == 'wfo' || m == 'wfh') ? m : null;

  Future<Map<String, String>> _signAvatars(Map<String, String> byEmp) async {
    final paths = byEmp.values.where((p) => !p.startsWith('http')).toSet().toList();
    final out = <String, String>{};
    for (final e in byEmp.entries) {
      if (e.value.startsWith('http')) out[e.value] = e.value;
    }
    if (paths.isEmpty) return out;
    try {
      final res = await supabase.storage.from('avatars').createSignedUrls(paths, 3600);
      for (final r in res) {
        if (r.signedUrl.isNotEmpty) out[r.path] = r.signedUrl;
      }
    } catch (_) {}
    return out;
  }
}
