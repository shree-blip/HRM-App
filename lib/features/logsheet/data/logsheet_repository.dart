import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/attendance_time.dart';
import 'log_models.dart';

/// Log Sheet data access (work_logs + clients + work_log_history + alerts).
/// Team/live/report scoping relies on RLS (manager → team, VP/Admin → all),
/// matching how the other team views work. No schema changes.
class LogSheetRepository {
  static const _logCols =
      'id, user_id, employee_id, client_id, department, log_date, '
      'task_description, time_spent_minutes, notes, start_time, end_time, '
      'status, pause_start, total_pause_minutes, created_at, '
      'client:clients(name, client_id)';

  static const _teamCols =
      'id, user_id, employee_id, client_id, department, log_date, '
      'task_description, time_spent_minutes, notes, start_time, end_time, '
      'status, pause_start, total_pause_minutes, created_at, '
      'client:clients(name, client_id), '
      'employee:employees(first_name, last_name, department)';

  String get _uid => supabase.auth.currentUser!.id;

  // ── Current employee context (for inserts) ──────────────
  ({String? employeeId, String? orgId, String? department})? _ctx;
  Future<({String? employeeId, String? orgId, String? department})> _context() async {
    if (_ctx != null) return _ctx!;
    String? empId;
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': _uid});
      if (r is String) empId = r;
    } catch (_) {}
    String? orgId;
    String? dept;
    if (empId != null) {
      try {
        final emp = await supabase
            .from('employees')
            .select('org_id, department')
            .eq('id', empId)
            .maybeSingle();
        orgId = emp?['org_id'] as String?;
        dept = emp?['department'] as String?;
      } catch (_) {}
    }
    return _ctx = (employeeId: empId, orgId: orgId, department: dept);
  }

  // ── Clients ─────────────────────────────────────────────
  Future<List<Client>> clients() async {
    final rows = await supabase
        .from('clients')
        .select('id, name, client_id')
        .eq('is_active', true)
        .order('name', ascending: true);
    return (rows as List)
        .map((r) => Client.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<LogEmployee>> employees() async {
    final rows = await supabase
        .from('employees')
        .select('id, first_name, last_name, department, employee_id, email')
        .order('first_name', ascending: true);
    return (rows as List)
        .map((r) => LogEmployee.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> addClient(String name, String? code) async {
    final ctx = await _context();
    final clean = name.trim();
    await supabase.from('clients').insert({
      'name': clean.isEmpty ? clean : clean[0].toUpperCase() + clean.substring(1),
      if (code != null && code.trim().isNotEmpty) 'client_id': code.trim(),
      if (ctx.orgId != null) 'org_id': ctx.orgId,
      'created_by': _uid,
    });
  }

  Future<List<Map<String, dynamic>>> alertsForClient(String clientId) async {
    final rows = await supabase
        .from('client_alerts')
        .select('id, title, message, alert_type, expires_at')
        .eq('client_id', clientId)
        .eq('is_active', true)
        .eq('show_on_selection', true)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
  }

  // ── Reads ───────────────────────────────────────────────
  Future<List<WorkLog>> myLogs(String date) async {
    final rows = await supabase
        .from('work_logs')
        .select(_logCols)
        .eq('user_id', _uid)
        .eq('log_date', date)
        .order('created_at', ascending: false);
    return _map(rows);
  }

  /// Team logs for [date]. Pass [scopeUserIds] to limit to a manager's team
  /// (web useWorkLogs.fetchTeamLogs: VP org-wide minus self, every other
  /// manager .in(user_id, team)).
  Future<List<WorkLog>> teamLogs(String date, {List<String>? scopeUserIds}) async {
    if (scopeUserIds != null && scopeUserIds.isEmpty) return const [];
    var query = supabase
        .from('work_logs')
        .select(_teamCols)
        .eq('log_date', date)
        .neq('user_id', _uid);
    if (scopeUserIds != null) {
      query = query.inFilter('user_id', scopeUserIds);
    }
    final rows = await query.order('created_at', ascending: false);
    return _map(rows);
  }

  /// Live in-progress team logs (web TeamRealtimeDashboard scoping).
  Future<List<WorkLog>> liveLogs(String today, {List<String>? scopeUserIds}) async {
    if (scopeUserIds != null && scopeUserIds.isEmpty) return const [];
    var query = supabase
        .from('work_logs')
        .select(_teamCols)
        .eq('log_date', today)
        .eq('status', 'in_progress')
        .neq('user_id', _uid);
    if (scopeUserIds != null) {
      query = query.inFilter('user_id', scopeUserIds);
    }
    final rows =
        await query.order('created_at', ascending: false).limit(20);
    return _map(rows);
  }

  Future<List<WorkLog>> reportLogs({
    required String start,
    required String end,
    String? clientId,
    String? employeeId,
    String? department,
    List<String>? scopeUserIds,
  }) async {
    if (scopeUserIds != null && scopeUserIds.isEmpty) return const [];
    // Paginate (1000/page) to bypass the default row cap, like the web report.
    const pageSize = 1000;
    final all = <WorkLog>[];
    var from = 0;
    while (true) {
      var q = supabase
          .from('work_logs')
          .select(_teamCols)
          .gte('log_date', start)
          .lte('log_date', end);
      if (clientId != null) q = q.eq('client_id', clientId);
      if (employeeId != null) q = q.eq('employee_id', employeeId);
      if (department != null) q = q.eq('department', department);
      if (scopeUserIds != null) q = q.inFilter('user_id', scopeUserIds);
      final rows = await q
          .order('log_date', ascending: false)
          .range(from, from + pageSize - 1);
      final batch = _map(rows);
      all.addAll(batch);
      if (batch.length < pageSize) break;
      from += pageSize;
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> history(String logId) async {
    final rows = await supabase
        .from('work_log_history')
        .select()
        .eq('work_log_id', logId)
        .order('changed_at', ascending: false);
    return (rows as List).map((r) => (r as Map).cast<String, dynamic>()).toList();
  }

  List<WorkLog> _map(dynamic rows) => (rows as List)
      .map((r) => WorkLog.fromMap((r as Map).cast<String, dynamic>()))
      .toList();

  // ── Writes ──────────────────────────────────────────────
  String _nowHm() {
    final n = DateTime.now().toUtc().add(NptTime.offset);
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  Future<void> addLog({
    required String logDate,
    required String taskDescription,
    String? clientId,
    String? department,
    String? startTime,
    String? endTime,
    String? notes,
  }) async {
    final ctx = await _context();
    // Auto-pause any existing in_progress logs for this user.
    await supabase
        .from('work_logs')
        .update({'status': 'on_hold', 'pause_start': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', _uid)
        .eq('status', 'in_progress');

    final start = startTime ?? _nowHm();
    final status = endTime != null && endTime.isNotEmpty ? 'completed' : 'in_progress';
    final mins = endTime != null && endTime.isNotEmpty
        ? minutesBetween(start, endTime)
        : 0;
    await supabase.from('work_logs').insert({
      'user_id': _uid,
      if (ctx.employeeId != null) 'employee_id': ctx.employeeId,
      if (ctx.orgId != null) 'org_id': ctx.orgId,
      'log_date': logDate,
      'task_description': taskDescription.trim(),
      'time_spent_minutes': mins,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (clientId != null) 'client_id': clientId,
      'department': department ?? ctx.department,
      'start_time': start,
      if (endTime != null && endTime.isNotEmpty) 'end_time': endTime,
      'status': status,
    });
  }

  Future<void> updateLog(
    WorkLog old, {
    String? taskDescription,
    Object? clientId = _unset,
    String? department,
    String? startTime,
    Object? endTime = _unset,
    String? notes,
    String? status,
  }) async {
    final newStart = startTime ?? old.startTime;
    var newEnd = endTime == _unset ? old.endTime : endTime as String?;
    var newStatus = status ?? old.status;
    // end_time set with no explicit status → completed.
    if (endTime != _unset && newEnd != null && status == null) {
      newStatus = 'completed';
    }
    // completed with no end_time → stamp now.
    if (newStatus == 'completed' && (newEnd == null || newEnd.isEmpty)) {
      newEnd = _nowHm();
    }
    final mins = (minutesBetween(newStart, newEnd) - old.totalPauseMinutes)
        .clamp(0, 1 << 31);

    final update = <String, dynamic>{
      if (taskDescription != null) 'task_description': taskDescription.trim(),
      if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim(),
      if (clientId != _unset) 'client_id': clientId,
      if (department != null) 'department': department,
      if (startTime != null) 'start_time': newStart,
      if (endTime != _unset) 'end_time': newEnd,
      'status': newStatus,
      'time_spent_minutes': mins,
    };
    await _writeHistory(old, update);
    await supabase.from('work_logs').update(update).eq('id', old.id);
  }

  /// Re-fetch the current DB row before computing pause/complete updates —
  /// the local model may be stale (e.g. the log was paused from the web app),
  /// which corrupted pause totals. Mirrors the web pauseLog/resumeLog, which
  /// always select the fresh row first.
  Future<WorkLog> _fresh(WorkLog log) async {
    try {
      final row = await supabase
          .from('work_logs')
          .select(_logCols)
          .eq('id', log.id)
          .maybeSingle();
      if (row != null) return WorkLog.fromMap(row.cast<String, dynamic>());
    } catch (_) {}
    return log;
  }

  Future<void> pauseLog(WorkLog log) async {
    final fresh = await _fresh(log);
    final update = {
      'status': 'on_hold',
      'pause_start': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeHistory(fresh, update);
    await supabase.from('work_logs').update(update).eq('id', fresh.id);
  }

  Future<void> resumeLog(WorkLog log) async {
    final fresh = await _fresh(log);
    final addMin = fresh.pauseStart != null
        ? DateTime.now().toUtc().difference(fresh.pauseStart!).inMinutes.clamp(0, 1 << 31)
        : 0;
    final update = {
      'status': 'in_progress',
      'pause_end': DateTime.now().toUtc().toIso8601String(),
      'total_pause_minutes': fresh.totalPauseMinutes + addMin,
      'end_time': null,
    };
    await _writeHistory(fresh, update);
    await supabase.from('work_logs').update(update).eq('id', fresh.id);
  }

  Future<void> completeLog(WorkLog log) async {
    final fresh = await _fresh(log);
    final end = _nowHm();
    final mins = (minutesBetween(fresh.startTime, end) - fresh.totalPauseMinutes)
        .clamp(0, 1 << 31);
    final update = {
      'status': 'completed',
      'end_time': end,
      'time_spent_minutes': mins,
    };
    await _writeHistory(fresh, update);
    await supabase.from('work_logs').update(update).eq('id', fresh.id);
  }

  Future<void> deleteLog(String id) async {
    await supabase.from('work_logs').delete().eq('id', id);
  }

  Future<void> _writeHistory(WorkLog old, Map<String, dynamic> n) async {
    try {
      await supabase.from('work_log_history').insert({
        'work_log_id': old.id,
        'user_id': _uid,
        'change_type': 'update',
        'previous_task_description': old.taskDescription,
        'new_task_description': n['task_description'] ?? old.taskDescription,
        'previous_time_spent_minutes': old.timeSpentMinutes,
        'new_time_spent_minutes': n['time_spent_minutes'] ?? old.timeSpentMinutes,
        'previous_notes': old.notes,
        'new_notes': n.containsKey('notes') ? n['notes'] : old.notes,
        'previous_start_time': old.startTime,
        'new_start_time': n['start_time'] ?? old.startTime,
        'previous_end_time': old.endTime,
        'new_end_time': n.containsKey('end_time') ? n['end_time'] : old.endTime,
        'previous_status': old.status,
        'new_status': n['status'] ?? old.status,
        'previous_client_id': old.clientId,
        'new_client_id': n.containsKey('client_id') ? n['client_id'] : old.clientId,
        'previous_department': old.department,
        'new_department': n['department'] ?? old.department,
        'previous_total_pause_minutes': old.totalPauseMinutes,
        'new_total_pause_minutes': n['total_pause_minutes'] ?? old.totalPauseMinutes,
      });
    } catch (_) {}
  }

  static const _unset = Object();
}
