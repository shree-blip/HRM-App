import '../../../core/supabase/supabase_client.dart';
import '../../support/data/comment_models.dart';
import 'task_models.dart';

class AssignableUser {
  const AssignableUser({required this.userId, required this.name});
  final String userId;
  final String name;
}

class TaskClient {
  const TaskClient({required this.id, required this.name, this.code});
  final String id;
  final String name;
  final String? code;
}

/// Tasks data access (tasks + task_assignees + task_comments). Visibility:
/// created_by OR assigned. Mirrors useTasks. No schema changes.
class TasksRepository {
  String get _uid => supabase.auth.currentUser!.id;

  Future<List<TaskItem>> fetchTasks() async {
    final uid = _uid;
    final results = await Future.wait([
      supabase
          .from('tasks')
          .select('id, title, description, client_name, client_id, created_by, '
              'priority, status, due_date, time_estimate, is_recurring, created_at')
          .order('created_at', ascending: false),
      supabase.from('task_assignees').select('task_id, user_id, assigned_by, assigned_at'),
      supabase.from('profiles').select('user_id, first_name, last_name'),
      supabase.from('task_comments').select('task_id'),
    ]);

    final tasks = (results[0] as List).cast<Map>();
    final assignees = (results[1] as List).cast<Map>();
    final profiles = (results[2] as List).cast<Map>();
    final comments = (results[3] as List).cast<Map>();

    final names = <String, String>{
      for (final p in profiles) p['user_id'] as String: '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
    };
    final commentCount = <String, int>{};
    for (final c in comments) {
      final t = c['task_id'] as String;
      commentCount[t] = (commentCount[t] ?? 0) + 1;
    }
    final byTask = <String, List<TaskAssignee>>{};
    final assignedToMe = <String>{};
    for (final a in assignees) {
      final t = a['task_id'] as String;
      final u = a['user_id'] as String;
      (byTask[t] ??= []).add(TaskAssignee(userId: u, name: names[u] ?? 'Unknown'));
      if (u == uid) assignedToMe.add(t);
    }

    final all = [
      for (final t in tasks)
        TaskItem(
          id: t['id'] as String,
          title: (t['title'] ?? '') as String,
          description: t['description'] as String?,
          clientName: t['client_name'] as String?,
          clientId: t['client_id'] as String?,
          createdBy: (t['created_by'] ?? '') as String,
          createdByName: names[t['created_by']] ?? 'Unknown',
          priority: (t['priority'] ?? 'medium') as String,
          status: (t['status'] ?? 'todo') as String,
          dueDate: t['due_date'] as String?,
          timeEstimate: t['time_estimate'] as String?,
          assignees: byTask[t['id']] ?? const [],
          commentCount: commentCount[t['id']] ?? 0,
        ),
    ];
    // Visibility: creator OR assigned.
    return all.where((t) => t.createdBy == uid || assignedToMe.contains(t.id)).toList();
  }

  Future<List<AssignableUser>> assignableUsers() async {
    final rows = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name')
        .order('first_name', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map;
      return AssignableUser(
        userId: m['user_id'] as String,
        name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
      );
    }).toList();
  }

  Future<List<TaskClient>> clients() async {
    final rows = await supabase
        .from('clients')
        .select('id, name, client_id')
        .eq('is_active', true)
        .order('name', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map;
      return TaskClient(id: m['id'] as String, name: (m['name'] ?? '') as String, code: m['client_id'] as String?);
    }).toList();
  }

  Future<void> addClient(String name, String? code) async {
    String? orgId;
    try {
      final o = await supabase.rpc('get_user_org_id', params: {'_user_id': _uid});
      if (o is String) orgId = o;
    } catch (_) {}
    final clean = name.trim();
    await supabase.from('clients').insert({
      'name': clean.isEmpty ? clean : clean[0].toUpperCase() + clean.substring(1),
      if (code != null && code.trim().isNotEmpty) 'client_id': code.trim(),
      'created_by': _uid,
      if (orgId != null) 'org_id': orgId,
    });
  }

  Future<void> createTask({
    required String title,
    String? description,
    String? clientName,
    String? clientId,
    required String priority,
    required String status,
    DateTime? dueDate,
    required List<String> assigneeIds,
  }) async {
    String? orgId;
    try {
      final o = await supabase.rpc('get_user_org_id', params: {'_user_id': _uid});
      if (o is String) orgId = o;
    } catch (_) {}
    final inserted = await supabase
        .from('tasks')
        .insert({
          'title': title.trim(),
          'description': description,
          'client_name': clientName,
          'client_id': clientId,
          'created_by': _uid,
          'priority': priority,
          'status': status,
          'due_date': dueDate?.toIso8601String().split('T').first,
          'is_recurring': false,
          if (orgId != null) 'org_id': orgId,
        })
        .select('id')
        .single();
    final taskId = inserted['id'] as String;
    if (assigneeIds.isNotEmpty) {
      await supabase.from('task_assignees').insert([
        for (final a in assigneeIds) {'task_id': taskId, 'user_id': a, 'assigned_by': _uid},
      ]);
      await _notify(assigneeIds, 'New Task Assigned', 'You were assigned a new task: "${title.trim()}"');
    }
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    String? clientName,
    Object? clientId = _unset,
    String? priority,
    String? status,
    String? timeEstimate,
  }) async {
    await supabase.from('tasks').update({
      if (title != null) 'title': title.trim(),
      if (description != null) 'description': description,
      if (clientName != null) 'client_name': clientName,
      if (clientId != _unset) 'client_id': clientId,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (timeEstimate != null) 'time_estimate': timeEstimate,
    }).eq('id', id);
  }

  Future<void> updateTaskAssignees(String taskId, List<String> assigneeIds) async {
    final existing = await supabase.from('task_assignees').select('user_id').eq('task_id', taskId);
    final existingIds = (existing as List).map((e) => (e as Map)['user_id'] as String).toSet();
    final newIds = assigneeIds.where((id) => !existingIds.contains(id)).toList();
    await supabase.from('task_assignees').delete().eq('task_id', taskId);
    if (assigneeIds.isNotEmpty) {
      await supabase.from('task_assignees').insert([
        for (final a in assigneeIds) {'task_id': taskId, 'user_id': a, 'assigned_by': _uid},
      ]);
      if (newIds.isNotEmpty) {
        final t = await supabase.from('tasks').select('title').eq('id', taskId).maybeSingle();
        await _notify(newIds, 'Task Assigned', 'You were assigned to a task: "${t?['title'] ?? 'Untitled'}"');
      }
    }
  }

  Future<void> updateTaskStatus(String taskId, String status) async {
    await supabase.from('tasks').update({'status': status}).eq('id', taskId);
    try {
      final t = await supabase.from('tasks').select('title').eq('id', taskId).maybeSingle();
      final a = await supabase.from('task_assignees').select('user_id').eq('task_id', taskId);
      final ids = (a as List).map((e) => (e as Map)['user_id'] as String).toList();
      await _notify(ids, '📋 Task Status Updated',
          '"${t?['title'] ?? 'A task'}" moved to ${taskStatusLabel(status)}.',);
    } catch (_) {}
  }

  Future<void> deleteTask(String id) async {
    await supabase.from('tasks').delete().eq('id', id);
  }

  // ── Comments ──────────────────────────────────────────
  Future<List<CommentItem>> comments(String taskId) async {
    final rows = await supabase
        .from('task_comments')
        .select('id, user_id, content, created_at')
        .eq('task_id', taskId)
        .order('created_at', ascending: true);
    final list = (rows as List).map((r) => CommentItem.fromMap((r as Map).cast<String, dynamic>())).toList();
    if (list.isEmpty) return list;
    final ids = list.map((c) => c.userId).toSet().toList();
    final names = <String, String>{};
    final profs = await supabase.from('profiles').select('user_id, first_name, last_name').inFilter('user_id', ids);
    for (final p in profs as List) {
      final m = p as Map;
      names[m['user_id'] as String] = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    }
    return list.map((c) => c.withAuthor(names[c.userId] ?? 'Unknown')).toList();
  }

  Future<void> addComment(String taskId, String content) async {
    await supabase.from('task_comments').insert({'task_id': taskId, 'user_id': _uid, 'content': content.trim()});
    try {
      final t = await supabase.from('tasks').select('title, created_by').eq('id', taskId).maybeSingle();
      final a = await supabase.from('task_assignees').select('user_id').eq('task_id', taskId);
      final targets = <String>{};
      if (t?['created_by'] != null) targets.add(t!['created_by'] as String);
      for (final x in a as List) {
        targets.add((x as Map)['user_id'] as String);
      }
      await _notify(targets.toList(), '💬 New Task Comment', 'New comment on "${t?['title'] ?? 'a task'}".');
    } catch (_) {}
  }

  Future<void> deleteComment(String id) async {
    await supabase.from('task_comments').delete().eq('id', id);
  }

  Future<void> _notify(List<String> userIds, String title, String message) async {
    for (final u in userIds.toSet()) {
      if (u == _uid) continue;
      try {
        await supabase.rpc('create_notification', params: {
          'p_user_id': u,
          'p_title': title,
          'p_message': message,
          'p_type': 'task',
          'p_link': '/tasks',
        },);
      } catch (_) {}
    }
  }

  static const _unset = Object();
}
