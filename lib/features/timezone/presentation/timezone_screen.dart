import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../data/timezone_models.dart';
import '../data/timezone_providers.dart';
import '../data/tz_utils.dart';

/// Timezone Management (parity with the web page): per-employee IANA timezone
/// list with search/filter, single + bulk update (with change log), live local
/// time, status badges, and CSV export. Gated by manage_access.
class TimezoneScreen extends ConsumerStatefulWidget {
  const TimezoneScreen({super.key});
  @override
  ConsumerState<TimezoneScreen> createState() => _TimezoneScreenState();
}

class _TimezoneScreenState extends ConsumerState<TimezoneScreen> {
  String _query = '';
  String _filterTz = 'all';
  final Set<String> _selected = {};
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh local times every 60s (web parity).
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<EmployeeTimezoneRow> _filter(List<EmployeeTimezoneRow> all) {
    final q = _query.toLowerCase();
    return all.where((e) {
      final matchesSearch = q.isEmpty || e.fullName.toLowerCase().contains(q) || (e.department ?? '').toLowerCase().contains(q);
      final matchesTz = _filterTz == 'all' || e.timezone == _filterTz;
      return matchesSearch && matchesTz;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsControllerProvider);
    final canManage = canManageTimezones(ref);
    final stillResolving = perms.loading && !canManage;
    final async = ref.watch(timezoneEmployeesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Timezone Management')),
      drawer: const AppDrawer(currentRoute: '/timezone-management'),
      body: stillResolving
          ? const Center(child: CircularProgressIndicator())
          : !canManage
              ? const _NoAccess()
              : async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Could not load.\n$e', textAlign: TextAlign.center)),
                  data: (all) => _buildBody(context, all),
                ),
    );
  }

  Widget _buildBody(BuildContext context, List<EmployeeTimezoneRow> all) {
    final theme = Theme.of(context);
    final filtered = _filter(all);
    final uniqueTz = (all.map((e) => e.timezone).toSet().toList()..sort());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text("Attendance times are recorded in each employee's assigned timezone. Keep these accurate.",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search by name or department'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            _tzFilter(context, uniqueTz),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export'),
              onPressed: () => _export(filtered),
            ),
            const SizedBox(width: 8),
            if (_selected.length >= 2)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                label: Text('Bulk Update (${_selected.length})'),
                onPressed: () => _openBulk(all),
              ),
          ],),
        ),
        // Select-all row
        if (filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Checkbox(
                value: _selected.length == filtered.length && filtered.isNotEmpty,
                onChanged: (_) => setState(() {
                  if (_selected.length == filtered.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(filtered.map((e) => e.id));
                  }
                }),
              ),
              Text('Select all (${filtered.length})', style: theme.textTheme.bodySmall),
            ],),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('No employees found', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _employeeCard(context, filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _tzFilter(BuildContext context, List<String> uniqueTz) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.public, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _filterTz,
            isDense: true,
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All Timezones')),
              for (final tz in uniqueTz) DropdownMenuItem(value: tz, child: Text('$tz (${getTimezoneAbbr(tz)})')),
            ],
            onChanged: (v) => setState(() => _filterTz = v ?? 'all'),
          ),
        ),
      ],),
    );
  }

  Widget _employeeCard(BuildContext context, EmployeeTimezoneRow e) {
    final theme = Theme.of(context);
    final selected = _selected.contains(e.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: (_) => setState(() => selected ? _selected.remove(e.id) : _selected.add(e.id))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(e.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
                    _statusBadge(context, e.timezoneStatus),
                  ],),
                  Text('${e.jobTitle ?? '-'}${e.department != null ? ' · ${e.department}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.public, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(child: Text('${e.timezone}  ·  ${getTimezoneAbbr(e.timezone)} ${getUtcOffsetString(e.timezone)}', style: theme.textTheme.bodySmall)),
                  ],),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${getCurrentLocalTime(e.timezone)} ${getTimezoneAbbr(e.timezone)}',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),),
                    const Spacer(),
                    TextButton(onPressed: () => _openEdit(e), child: const Text('Edit')),
                  ],),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(BuildContext context, String status) {
    final (Color c, IconData icon, String label) = switch (status) {
      'verified' => (Colors.green.shade700, Icons.check, 'Verified'),
      'conflict' => (Theme.of(context).colorScheme.error, Icons.warning_amber_rounded, 'Conflict'),
      _ => (Colors.orange.shade800, Icons.warning_amber_rounded, 'Default'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
      ],),
    );
  }

  // ── Edit single ──
  Future<void> _openEdit(EmployeeTimezoneRow e) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _EditTimezoneForm(employee: e),
      ),
    );
    if (changed == true) ref.invalidate(timezoneEmployeesProvider);
  }

  // ── Bulk ──
  Future<void> _openBulk(List<EmployeeTimezoneRow> all) async {
    final selectedRows = all.where((e) => _selected.contains(e.id)).toList();
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _BulkTimezoneForm(employees: selectedRows),
      ),
    );
    if (changed == true) {
      setState(_selected.clear);
      ref.invalidate(timezoneEmployeesProvider);
    }
  }

  // ── CSV export ──
  Future<void> _export(List<EmployeeTimezoneRow> rows) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      String esc(String s) => '"${s.replaceAll('"', '""')}"';
      final header = ['Name', 'Department', 'Role', 'Timezone', 'UTC Offset', 'Status'].join(',');
      final lines = rows.map((e) => [
            esc(e.fullName),
            esc(e.department ?? '-'),
            esc(e.jobTitle ?? '-'),
            esc(e.timezone),
            esc(getUtcOffsetString(e.timezone)),
            esc(e.timezoneStatus),
          ].join(','),);
      final csv = ([header, ...lines]).join('\n');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/employee-timezones.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: 'Employee Timezones', text: 'Timezone list (${rows.length} employees)');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Access Denied', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text("You don't have permission to access this page.", textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],),
      ),
    );
  }
}

// ════════════════ Edit single form ════════════════
class _EditTimezoneForm extends ConsumerStatefulWidget {
  const _EditTimezoneForm({required this.employee});
  final EmployeeTimezoneRow employee;
  @override
  ConsumerState<_EditTimezoneForm> createState() => _EditTimezoneFormState();
}

class _EditTimezoneFormState extends ConsumerState<_EditTimezoneForm> {
  late String _tz;
  final _reason = TextEditingController();
  bool _markVerified = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tz = kCommonTimezones.contains(widget.employee.timezone) ? widget.employee.timezone : kCommonTimezones.first;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await ref.read(timezoneRepositoryProvider).updateTimezone(
            employee: widget.employee,
            newTimezone: _tz,
            reason: _reason.text,
            markVerified: _markVerified,
          );
      nav.pop(true);
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
    final e = widget.employee;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Update Timezone — ${e.fullName}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Current Timezone'),
            child: Text('${e.timezone} (${getUtcOffsetString(e.timezone)})'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _tz,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'New Timezone'),
            items: [for (final tz in kCommonTimezones) DropdownMenuItem(value: tz, child: Text('$tz — ${getTimezoneAbbr(tz)} (${getUtcOffsetString(tz)})', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _tz = v ?? _tz),
          ),
          const SizedBox(height: 10),
          TextField(controller: _reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason *', hintText: 'Why is this timezone being changed?', alignLabelWithHint: true)),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _markVerified,
            onChanged: (v) => setState(() => _markVerified = v ?? false),
            title: const Text('Mark as Verified (removes ⚠ Default badge)'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Text('Historical UTC records are preserved. Only how past records are displayed will change.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || _reason.text.trim().isEmpty ? null : _save,
              child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Timezone'),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════ Bulk form ════════════════
class _BulkTimezoneForm extends ConsumerStatefulWidget {
  const _BulkTimezoneForm({required this.employees});
  final List<EmployeeTimezoneRow> employees;
  @override
  ConsumerState<_BulkTimezoneForm> createState() => _BulkTimezoneFormState();
}

class _BulkTimezoneFormState extends ConsumerState<_BulkTimezoneForm> {
  String? _tz;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_tz == null || _reason.text.trim().isEmpty) {
      setState(() => _error = 'Select a timezone and enter a reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await ref.read(timezoneRepositoryProvider).bulkUpdate(employees: widget.employees, newTimezone: _tz!, reason: _reason.text);
      nav.pop(true);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bulk Timezone Update', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Updating ${widget.employees.length} employee(s):', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final e in widget.employees) Text('• ${e.fullName}', style: theme.textTheme.bodySmall)],
              ),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _tz,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'New Timezone'),
            items: [for (final tz in kCommonTimezones) DropdownMenuItem(value: tz, child: Text('$tz — ${getTimezoneAbbr(tz)} (${getUtcOffsetString(tz)})', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _tz = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason *', hintText: 'Reason for bulk timezone change', alignLabelWithHint: true)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Update ${widget.employees.length} Employees'),
            ),
          ),
        ],
      ),
    );
  }
}
