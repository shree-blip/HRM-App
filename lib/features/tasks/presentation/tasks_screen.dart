import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/task_models.dart';
import '../data/tasks_providers.dart';
import 'task_dialogs.dart';

/// Tasks (Critical Fix 3): Kanban board (To Do / In Progress / Review / Done)
/// with create/edit/delete, assignees, priority, due date, move-between-columns,
/// comments, and search. Mirrors the web Tasks page. Visibility: created or
/// assigned. Route gated by view_tasks / manage_tasks.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tasksControllerProvider);
    final q = _q.toLowerCase();
    List<TaskItem> byStatus(String s) => state.items
        .where((t) =>
            t.status == s &&
            (t.title.toLowerCase().contains(q) || (t.clientName ?? '').toLowerCase().contains(q)),)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      drawer: const AppDrawer(currentRoute: '/tasks'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTaskForm(context, ref, defaultStatus: 'todo'),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search tasks by title or client',
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (state.loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final col in kTaskColumns)
                      SizedBox(width: 300, child: _Column(id: col.$1, title: col.$2, tasks: byStatus(col.$1))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Column extends ConsumerWidget {
  const _Column({required this.id, required this.title, required this.tasks});
  final String id;
  final String title;
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (_, fg) = taskColumnColor(id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Icon(taskColumnIcon(id), size: 16, color: fg),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
                child: Text('${tasks.length}', style: theme.textTheme.labelSmall),
              ),
            ],),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text('No tasks', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 80),
                    children: [for (final t in tasks) _TaskCard(task: t)],
                  ),
          ),
          if (id == 'todo')
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Task'),
              onPressed: () => showTaskForm(context, ref, defaultStatus: 'todo'),
            ),
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task});
  final TaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pc = priorityColor(task.priority);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => showTaskDetail(context, ref, task),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: pc), borderRadius: BorderRadius.circular(6)),
                    child: Text(task.priority, style: TextStyle(color: pc, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: (v) {
                      if (v == 'edit') {
                        showTaskForm(context, ref, existing: task);
                      } else if (v == 'delete') {
                        _confirmDelete(context, ref);
                      } else if (v.startsWith('move:')) {
                        ref.read(tasksControllerProvider.notifier).moveTask(task.id, v.substring(5));
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit Task')),
                      const PopupMenuDivider(),
                      for (final c in kTaskColumns)
                        if (c.$1 != task.status)
                          PopupMenuItem(value: 'move:${c.$1}', child: Text('Move to ${c.$2}')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Color(0xFFDC2626)))),
                    ],
                  ),
                ],
              ),
              Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(task.clientName ?? 'Internal', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (task.description != null && task.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(task.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant),),
                ),
              if (task.createdByName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('by ${task.createdByName}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _avatars(theme)),
                  if (task.commentCount > 0) ...[
                    Icon(Icons.mode_comment_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text('${task.commentCount}', style: theme.textTheme.labelSmall),
                    const SizedBox(width: 8),
                  ],
                  Icon(Icons.event_outlined, size: 13, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(dueDisplay(task.dueDate), style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatars(ThemeData theme) {
    if (task.assignees.isEmpty) {
      return Text('Unassigned', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    final shown = task.assignees.take(3).toList();
    return Row(
      children: [
        for (final a in shown)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: CircleAvatar(
              radius: 11,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(a.initials, style: TextStyle(fontSize: 9, color: theme.colorScheme.onPrimaryContainer)),
            ),
          ),
        if (task.assignees.length > 3)
          Text('+${task.assignees.length - 3}', style: theme.textTheme.labelSmall),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete "${task.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(tasksControllerProvider.notifier).deleteTask(task.id);
  }
}
