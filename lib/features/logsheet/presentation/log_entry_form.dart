import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/attendance_time.dart';
import '../data/log_models.dart';
import '../data/logsheet_providers.dart';

/// Bottom-sheet form to add or edit a work log entry (ports the web add/edit
/// dialog: task, client + client alerts, department, start/end, notes).
Future<bool?> showLogEntrySheet(
  BuildContext context, {
  required String logDate,
  WorkLog? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _LogEntryForm(logDate: logDate, existing: existing),
    ),
  );
}

class _LogEntryForm extends ConsumerStatefulWidget {
  const _LogEntryForm({required this.logDate, this.existing});
  final String logDate;
  final WorkLog? existing;

  @override
  ConsumerState<_LogEntryForm> createState() => _LogEntryFormState();
}

class _LogEntryFormState extends ConsumerState<_LogEntryForm> {
  late final TextEditingController _task;
  late final TextEditingController _notes;
  String? _clientId;
  String? _department;
  String? _start; // HH:mm
  String? _end;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _alerts = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _task = TextEditingController(text: e?.taskDescription ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _clientId = e?.clientId;
    _department = e?.department;
    // Web parity (handleOpenAddDialog): a NEW log defaults its start time to
    // "now" (NPT), so a clocked-in user need not set it manually. Editing keeps
    // the saved value.
    _start = e != null ? e.startTime : _nowNptHm();
    _end = e?.endTime;
    if (_clientId != null) _loadAlerts(_clientId!);
  }

  /// Current wall-clock time in NPT as HH:mm (matches the web's nowInTz()).
  static String _nowNptHm() {
    final npt = DateTime.now().toUtc().add(NptTime.offset);
    return '${npt.hour.toString().padLeft(2, '0')}:${npt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _task.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts(String clientId) async {
    try {
      final a = await ref.read(logSheetRepositoryProvider).alertsForClient(clientId);
      if (mounted) setState(() => _alerts = a);
    } catch (_) {}
  }

  Future<void> _pickTime(bool isStart) async {
    final now = TimeOfDay.now();
    final cur = (isStart ? _start : _end);
    final init = cur != null && cur.contains(':')
        ? TimeOfDay(
            hour: int.tryParse(cur.split(':')[0]) ?? now.hour,
            minute: int.tryParse(cur.split(':')[1]) ?? now.minute,)
        : now;
    final t = await showTimePicker(context: context, initialTime: init);
    if (t == null) return;
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => isStart ? _start = hm : _end = hm);
  }

  Future<void> _save() async {
    if (_task.text.trim().isEmpty) {
      setState(() => _error = 'Task description is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(logSheetRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateLog(
          widget.existing!,
          taskDescription: _task.text,
          clientId: _clientId,
          department: _department,
          startTime: _start,
          endTime: _end,
          notes: _notes.text,
        );
      } else {
        await repo.addLog(
          logDate: widget.logDate,
          taskDescription: _task.text,
          clientId: _clientId,
          department: _department,
          startTime: _start,
          endTime: _end,
          notes: _notes.text,
        );
      }
      ref.invalidate(myLogsProvider);
      ref.invalidate(teamLogsProvider);
      ref.invalidate(liveLogsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed: $e';
        });
      }
    }
  }

  /// Searchable client picker (web ClientCombobox parity): filter by client
  /// name or code so the user never scrolls a long list.
  Future<void> _pickClient(List<Client> clients) async {
    final selected = await showModalBottomSheet<({bool clear, String? id})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClientPickerSheet(clients: clients, current: _clientId),
    );
    if (selected == null) return; // dismissed
    setState(() {
      _clientId = selected.clear ? null : selected.id;
      _alerts = const [];
    });
    if (_clientId != null) _loadAlerts(_clientId!);
  }

  Future<void> _addClient() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddClientDialog(),
    );
    if (created == true) ref.invalidate(clientsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clients = ref.watch(clientsProvider).valueOrNull ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEdit ? 'Edit log entry' : 'Add log entry',
              style: theme.textTheme.titleLarge,),
          const SizedBox(height: 12),
          TextField(
            controller: _task,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Task description *',
              hintText: 'What are you working on?',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickClient(clients),
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Client (optional)',
                      suffixIcon: Icon(Icons.search, size: 18),
                    ),
                    child: Builder(builder: (_) {
                      final matches = clients.where((c) => c.id == _clientId);
                      final sel = (_clientId == null || matches.isEmpty) ? null : matches.first;
                      return Text(
                        sel?.display ?? 'No client',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sel == null ? theme.colorScheme.onSurfaceVariant : null,
                        ),
                      );
                    },),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add client',
                icon: const Icon(Icons.add_business_outlined),
                onPressed: _addClient,
              ),
            ],
          ),
          if (_alerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final a in _alerts)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a['title'] ?? 'Alert'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),),
                    if (a['message'] != null) Text('${a['message']}'),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: kDepartmentOptions.any((o) => o.value == _department)
                ? _department
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Department / Task type'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Default')),
              for (final o in kDepartmentOptions)
                DropdownMenuItem(value: o.value, child: Text(o.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _department = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _timeField('Start', _start, () => _pickTime(true))),
              const SizedBox(width: 12),
              Expanded(child: _timeField('End (optional)', _end, () => _pickTime(false))),
            ],
          ),
          const SizedBox(height: 4),
          Text('Leave End empty to keep the task in progress.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),)
                  : Text(_isEdit ? 'Save changes' : 'Add entry'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeField(String label, String? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.schedule, size: 18)),
        child: Text(value ?? 'Not set'),
      ),
    );
  }
}

/// Bottom-sheet client picker with a live search box (name or code).
class _ClientPickerSheet extends StatefulWidget {
  const _ClientPickerSheet({required this.clients, this.current});
  final List<Client> clients;
  final String? current;

  @override
  State<_ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends State<_ClientPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = widget.clients.where((c) {
      if (_q.isEmpty) return true;
      final hay = '${c.name} ${c.code ?? ''}'.toLowerCase();
      return hay.contains(_q);
    }).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select client', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search by name or code…',
                    ),
                    onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    dense: true,
                    leading: Icon(widget.current == null ? Icons.check_circle : Icons.circle_outlined,
                        size: 18, color: widget.current == null ? theme.colorScheme.primary : null,),
                    title: const Text('No client'),
                    onTap: () => Navigator.pop(context, (clear: true, id: null)),
                  ),
                  for (final c in filtered)
                    ListTile(
                      dense: true,
                      leading: Icon(c.id == widget.current ? Icons.check_circle : Icons.circle_outlined,
                          size: 18, color: c.id == widget.current ? theme.colorScheme.primary : null,),
                      title: Text(c.name),
                      subtitle: (c.code != null && c.code!.isNotEmpty) ? Text(c.code!) : null,
                      onTap: () => Navigator.pop(context, (clear: false, id: c.id)),
                    ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No clients match.')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddClientDialog extends ConsumerStatefulWidget {
  const _AddClientDialog();
  @override
  ConsumerState<_AddClientDialog> createState() => _AddClientDialogState();
}

class _AddClientDialogState extends ConsumerState<_AddClientDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add client'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name *')),
          const SizedBox(height: 8),
          TextField(controller: _code, decoration: const InputDecoration(labelText: 'Client ID (optional)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy || _name.text.trim().isEmpty
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  setState(() => _busy = true);
                  try {
                    await ref.read(logSheetRepositoryProvider).addClient(_name.text, _code.text);
                    nav.pop(true);
                  } catch (_) {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Edit-history dialog (work_log_history).
Future<void> showLogHistoryDialog(BuildContext context, WidgetRef ref, WorkLog log) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: ref.read(logSheetRepositoryProvider).history(log.id),
          builder: (context, snap) {
            final theme = Theme.of(context);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit history', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (!snap.hasData)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snap.data!.isEmpty)
                  const Text('No edits recorded.')
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final h in snap.data!) _historyTile(theme, h),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

Widget _historyTile(ThemeData theme, Map<String, dynamic> h) {
  final changes = <String>[];
  void diff(String label, dynamic a, dynamic b) {
    if ('$a' != '$b') changes.add('$label: ${a ?? '—'} → ${b ?? '—'}');
  }

  diff('Task', h['previous_task_description'], h['new_task_description']);
  diff('Status', h['previous_status'], h['new_status']);
  diff('Start', h['previous_start_time'], h['new_start_time']);
  diff('End', h['previous_end_time'], h['new_end_time']);
  diff('Time (min)', h['previous_time_spent_minutes'], h['new_time_spent_minutes']);
  diff('Notes', h['previous_notes'], h['new_notes']);
  final when = h['changed_at'] != null
      ? DateTime.tryParse(h['changed_at'] as String)?.toLocal().toString().substring(0, 16)
      : '';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(when ?? '', style: theme.textTheme.bodySmall),
        for (final c in changes) Text('• $c', style: theme.textTheme.bodySmall),
        if (changes.isEmpty) Text('• Updated', style: theme.textTheme.bodySmall),
      ],
    ),
  );
}
