import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../data/task_models.dart';
import '../data/tasks_providers.dart';

// ════════════════ Create / Edit form ════════════════
Future<void> showTaskForm(BuildContext context, WidgetRef ref, {TaskItem? existing, String? defaultStatus}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _TaskForm(existing: existing, defaultStatus: defaultStatus ?? 'todo'),
    ),
  );
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({this.existing, required this.defaultStatus});
  final TaskItem? existing;
  final String defaultStatus;
  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  String _clientId = 'internal';
  String _priority = 'medium';
  late String _status;
  DateTime? _due;
  final Set<String> _assignees = {};
  String _assigneeSearch = '';
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _priority = e?.priority ?? 'medium';
    _status = e?.status ?? widget.defaultStatus;
    _clientId = e?.clientId ?? 'internal';
    _due = e?.dueDate != null ? DateTime.tryParse(e!.dueDate!) : null;
    if (e != null) {
      _assignees.addAll(e.assignees.map((a) => a.userId));
    } else {
      final uid = ref.read(authControllerProvider).user?.id;
      if (uid != null) _assignees.add(uid);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a task title.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final clients = ref.read(taskClientsProvider).valueOrNull ?? const [];
    final isInternal = _clientId == 'internal';
    final clientName = isInternal ? 'Internal' : (clients.where((c) => c.id == _clientId).firstOrNull?.name ?? '');
    final ctrl = ref.read(tasksControllerProvider.notifier);
    try {
      if (_isEdit) {
        await ctrl.updateTask(
          widget.existing!.id,
          title: _title.text,
          description: _desc.text,
          clientName: clientName,
          clientId: isInternal ? null : _clientId,
          priority: _priority,
          status: _status,
        );
        await ctrl.updateAssignees(widget.existing!.id, _assignees.toList());
      } else {
        await ctrl.createTask(
          title: _title.text,
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          clientName: clientName,
          clientId: isInternal ? null : _clientId,
          priority: _priority,
          status: _status,
          dueDate: _due,
          assigneeIds: _assignees.toList(),
        );
      }
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clients = ref.watch(taskClientsProvider).valueOrNull ?? const [];
    final users = ref.watch(assignableUsersProvider).valueOrNull ?? const [];
    final myId = ref.read(authControllerProvider).user?.id;
    final filteredUsers = users.where((u) => u.name.toLowerCase().contains(_assigneeSearch.toLowerCase())).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEdit ? 'Edit Task' : 'Create New Task', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _clientId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Client'),
                items: [
                  const DropdownMenuItem(value: 'internal', child: Text('Internal')),
                  for (final c in clients) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _clientId = v ?? 'internal'),
              ),
            ),
            IconButton(tooltip: 'Add client', icon: const Icon(Icons.add_business_outlined), onPressed: _addClient),
          ],),
          const SizedBox(height: 10),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Task title *')),
          const SizedBox(height: 10),
          TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: [for (final p in kTaskPriorities) DropdownMenuItem(value: p, child: Text(p[0].toUpperCase() + p.substring(1)))],
                onChanged: (v) => setState(() => _priority = v ?? 'medium'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _due ?? DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 2));
                  if (d != null) setState(() => _due = d);
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Due date'), child: Text(_due == null ? 'No date' : dueDisplay(_due!.toIso8601String()))),
              ),
            ),
          ],),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [for (final s in kTaskStatuses) DropdownMenuItem(value: s, child: Text(taskStatusLabel(s)))],
            onChanged: (v) => setState(() => _status = v ?? 'todo'),
          ),
          const SizedBox(height: 12),
          Text('Assign to (${_assignees.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search people…'),
            onChanged: (v) => setState(() => _assigneeSearch = v),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final u in filteredUsers)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _assignees.contains(u.userId),
                    title: Text(u.userId == myId ? '${u.name} (Me)' : u.name),
                    onChanged: (_) => setState(() => _assignees.contains(u.userId) ? _assignees.remove(u.userId) : _assignees.add(u.userId)),
                  ),
                if (filteredUsers.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No users')),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save changes' : 'Create Task'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addClient() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add client'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
          const SizedBox(height: 8),
          TextField(controller: code, decoration: const InputDecoration(labelText: 'Client ID (optional)')),
        ],),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await ref.read(tasksRepositoryProvider).addClient(name.text, code.text);
      ref.invalidate(taskClientsProvider);
    }
  }
}

// ════════════════ Detail (view + comments) ════════════════
Future<void> showTaskDetail(BuildContext context, WidgetRef ref, TaskItem task) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TaskDetail(task: task),
  );
}

class _TaskDetail extends ConsumerStatefulWidget {
  const _TaskDetail({required this.task});
  final TaskItem task;
  @override
  ConsumerState<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends ConsumerState<_TaskDetail> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  TaskItem get t => widget.task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pc = priorityColor(t.priority);
    final comments = ref.watch(taskCommentsProvider(t.id));
    final myId = ref.read(authControllerProvider).user?.id;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(t.title, style: theme.textTheme.titleLarge)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: pc), borderRadius: BorderRadius.circular(6)),
                  child: Text(t.priority, style: TextStyle(color: pc, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _meta(theme, Icons.business, t.clientName ?? 'Internal'),
                _meta(theme, taskColumnIcon(t.status), taskStatusLabel(t.status)),
                _meta(theme, Icons.event_outlined, dueDisplay(t.dueDate)),
                if (t.createdByName != null) _meta(theme, Icons.person_outline, 'by ${t.createdByName}'),
              ],),
              if (t.description != null && t.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(t.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 8),
              if (t.assignees.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final a in t.assignees)
                    Chip(visualDensity: VisualDensity.compact, label: Text(a.name ?? 'User', style: const TextStyle(fontSize: 12))),
                ],),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                    onPressed: () {
                      Navigator.pop(context);
                      showTaskForm(context, ref, existing: t);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await ref.read(tasksControllerProvider.notifier).deleteTask(t.id);
                      nav.pop();
                    },
                  ),
                ),
              ],),
              const Divider(height: 24),
              comments.when(
                loading: () => const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                error: (_, __) => const Text('Could not load comments.'),
                data: (list) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Comments (${list.length})', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    if (list.isEmpty)
                      Text('No comments yet.', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                    for (final c in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(radius: 12, backgroundColor: theme.colorScheme.primaryContainer, child: Text((c.authorName ?? '?').isNotEmpty ? c.authorName![0].toUpperCase() : '?', style: const TextStyle(fontSize: 10))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.authorName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(c.content, style: theme.textTheme.bodyMedium),
                            ],),
                          ),
                          if (c.userId == myId)
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                              onPressed: () async {
                                await ref.read(tasksRepositoryProvider).deleteComment(c.id);
                                ref.invalidate(taskCommentsProvider(t.id));
                              },
                            ),
                        ],),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _comment, minLines: 1, maxLines: 3, decoration: const InputDecoration(isDense: true, hintText: 'Write a comment…'))),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    final txt = _comment.text.trim();
                    if (txt.isEmpty) return;
                    await ref.read(tasksRepositoryProvider).addComment(t.id, txt);
                    _comment.clear();
                    ref.invalidate(taskCommentsProvider(t.id));
                  },
                ),
              ],),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],);
}
