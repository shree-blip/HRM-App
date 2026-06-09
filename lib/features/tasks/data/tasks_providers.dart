import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../support/data/comment_models.dart';
import 'task_models.dart';
import 'tasks_repository.dart';

final tasksRepositoryProvider = Provider<TasksRepository>((_) => TasksRepository());

class TasksState {
  const TasksState({this.items = const [], this.loading = true});
  final List<TaskItem> items;
  final bool loading;
  TasksState copyWith({List<TaskItem>? items, bool? loading}) =>
      TasksState(items: items ?? this.items, loading: loading ?? this.loading);
}

final tasksControllerProvider =
    NotifierProvider<TasksController, TasksState>(TasksController.new);

class TasksController extends Notifier<TasksState> {
  RealtimeChannel? _channel;

  @override
  TasksState build() {
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_teardown);
    if (uid == null) {
      _teardown();
      return const TasksState(items: [], loading: false);
    }
    Future.microtask(_load);
    return const TasksState(loading: true);
  }

  TasksRepository get _repo => ref.read(tasksRepositoryProvider);

  Future<void> _load() async {
    try {
      final items = await _repo.fetchTasks();
      state = TasksState(items: items, loading: false);
    } catch (_) {
      state = const TasksState(items: [], loading: false);
    }
    _subscribe();
  }

  void _subscribe() {
    if (_channel != null) return;
    _channel = supabase.channel('tasks-changes')
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tasks', callback: (_) => refresh())
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'task_assignees', callback: (_) => refresh())
      ..subscribe();
  }

  Future<void> refresh() async {
    try {
      final items = await _repo.fetchTasks();
      state = state.copyWith(items: items, loading: false);
    } catch (_) {}
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
    await _repo.createTask(
      title: title, description: description, clientName: clientName, clientId: clientId,
      priority: priority, status: status, dueDate: dueDate, assigneeIds: assigneeIds,
    );
    await refresh();
  }

  Future<void> updateTask(String id, {String? title, String? description, String? clientName, Object? clientId = _u, String? priority, String? status, String? timeEstimate}) async {
    await _repo.updateTask(id, title: title, description: description, clientName: clientName, clientId: clientId, priority: priority, status: status, timeEstimate: timeEstimate);
    await refresh();
  }

  Future<void> updateAssignees(String taskId, List<String> ids) async {
    await _repo.updateTaskAssignees(taskId, ids);
    await refresh();
  }

  Future<void> moveTask(String taskId, String status) async {
    // optimistic
    state = state.copyWith(items: [
      for (final t in state.items)
        if (t.id == taskId)
          TaskItem(id: t.id, title: t.title, description: t.description, clientName: t.clientName, clientId: t.clientId, createdBy: t.createdBy, createdByName: t.createdByName, priority: t.priority, status: status, dueDate: t.dueDate, timeEstimate: t.timeEstimate, assignees: t.assignees, commentCount: t.commentCount)
        else
          t,
    ],);
    try {
      await _repo.updateTaskStatus(taskId, status);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> deleteTask(String id) async {
    final prev = state.items;
    state = state.copyWith(items: state.items.where((t) => t.id != id).toList());
    try {
      await _repo.deleteTask(id);
    } catch (_) {
      state = state.copyWith(items: prev);
    }
  }

  void _teardown() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  static const _u = Object();
}

final assignableUsersProvider =
    FutureProvider.autoDispose<List<AssignableUser>>((ref) => ref.read(tasksRepositoryProvider).assignableUsers());

final taskClientsProvider =
    FutureProvider.autoDispose<List<TaskClient>>((ref) => ref.read(tasksRepositoryProvider).clients());

final taskCommentsProvider = FutureProvider.autoDispose.family<List<CommentItem>, String>(
  (ref, taskId) => ref.read(tasksRepositoryProvider).comments(taskId),
);

/// Route access: view_tasks or manage_tasks (or manager/admin/vp).
bool canAccessTasks(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  final perms = ref.read(permissionsControllerProvider);
  return auth.isAdmin || auth.isVp || auth.isManager ||
      perms.has(Permission.viewTasks) || perms.has(Permission.manageTasks);
}
