import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import '../data/log_models.dart';
import '../data/logsheet_providers.dart';
import 'log_entry_form.dart';

/// Log Sheet (Phase 8): My Log / Live Log / Team Logs / Report.
/// Team tabs are gated to managers/VP/line-managers (data also RLS-scoped).
class LogSheetScreen extends ConsumerWidget {
  const LogSheetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final canTeam = auth.isManager || auth.isVp || auth.isLineManager || auth.isAdmin;

    final tabs = <Tab>[
      const Tab(text: 'My Log'),
      if (canTeam) const Tab(text: 'Live'),
      if (canTeam) const Tab(text: 'Team Logs'),
      if (canTeam) const Tab(text: 'Report'),
    ];
    final views = <Widget>[
      const _MyLogView(),
      if (canTeam) const _LiveLogView(),
      if (canTeam) const _TeamLogsView(),
      if (canTeam) const _ReportView(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Log Sheet'),
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        drawer: const AppDrawer(currentRoute: '/log-sheet'),
        body: TabBarView(children: views),
      ),
    );
  }
}

// ── Date selector ───────────────────────────────────────
class _DateBar extends ConsumerWidget {
  const _DateBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedLogDateProvider);
    void set(String d) => ref.read(selectedLogDateProvider.notifier).state = d;
    String shift(int days) {
      final d = DateTime.parse(date).add(Duration(days: days));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => set(shift(-1))),
          TextButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(date),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(date),
                firstDate: DateTime(DateTime.now().year - 2),
                lastDate: DateTime(DateTime.now().year + 1),
              );
              if (picked != null) {
                set('${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
              }
            },
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => set(shift(1))),
        ],
      ),
    );
  }
}

// ── My Log ──────────────────────────────────────────────
class _MyLogView extends ConsumerWidget {
  const _MyLogView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedLogDateProvider);
    final async = ref.watch(myLogsProvider);
    return Column(
      children: [
        const _DateBar(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add entry'),
                  onPressed: () => showLogEntrySheet(context, logDate: date),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: () => _exportMyLogs(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myLogsProvider);
              await ref.read(myLogsProvider.future);
            },
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
              data: (logs) => logs.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No log entries for this day.')))])
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [for (final l in logs) _LogCard(log: l, editable: true)],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportMyLogs(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final logs = ref.read(myLogsProvider).valueOrNull ?? const [];
    if (logs.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Nothing to export.')));
      return;
    }
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final rows = <String>[
      'Date,Task,Client,Client ID,Department,Start,End,Duration,Status,Notes',
      for (final l in logs)
        [
          q(l.logDate), q(l.taskDescription), q(l.clientName), q(l.clientCode),
          q(departmentLabel(l.department)), q(l.startTime), q(l.endTime),
          q(formatMinutes(l.timeSpentMinutes)), q(l.statusLabel), q(l.notes),
        ].join(','),
    ];
    await _share('my-logs', '\u{FEFF}${rows.join('\n')}', messenger);
  }
}

// ── Live Log (realtime) ─────────────────────────────────
class _LiveLogView extends ConsumerStatefulWidget {
  const _LiveLogView();
  @override
  ConsumerState<_LiveLogView> createState() => _LiveLogViewState();
}

class _LiveLogViewState extends ConsumerState<_LiveLogView> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _channel = supabase.channel('team-work-logs')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'work_logs',
        callback: (_) {
          if (mounted) ref.invalidate(liveLogsProvider);
        },
      ).subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(liveLogsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(liveLogsProvider);
        await ref.read(liveLogsProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
        data: (logs) => logs.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No one is actively logging right now.')))])
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Row(children: [
                      const Icon(Icons.bolt, color: Color(0xFF16A34A), size: 18),
                      const SizedBox(width: 4),
                      Text('${logs.length} working now',
                          style: const TextStyle(fontWeight: FontWeight.bold),),
                    ],),
                  ),
                  for (final l in logs) _LogCard(log: l, showEmployee: true),
                ],
              ),
      ),
    );
  }
}

// ── Team Logs ───────────────────────────────────────────
class _TeamLogsView extends ConsumerStatefulWidget {
  const _TeamLogsView();
  @override
  ConsumerState<_TeamLogsView> createState() => _TeamLogsViewState();
}

class _TeamLogsViewState extends ConsumerState<_TeamLogsView> {
  String _search = '';
  String _status = 'all';
  String? _employee;
  String? _client;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamLogsProvider);
    return Column(
      children: [
        const _DateBar(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search task / employee / client',
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(teamLogsProvider);
              await ref.read(teamLogsProvider.future);
            },
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
              data: (all) {
                final employees = {for (final l in all) if (l.employeeName != null && l.employeeId != null) l.employeeId!: l.employeeName!};
                final clients = {for (final l in all) if (l.clientName != null && l.clientId != null) l.clientId!: l.clientName!};
                var list = all.where((l) {
                  if (_status != 'all' && l.status != _status) return false;
                  if (_employee != null && l.employeeId != _employee) return false;
                  if (_client != null && l.clientId != _client) return false;
                  if (_search.isNotEmpty) {
                    final hay = '${l.taskDescription} ${l.employeeName ?? ''} ${l.clientName ?? ''}'.toLowerCase();
                    if (!hay.contains(_search)) return false;
                  }
                  return true;
                }).toList();
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        _filterChip('Status', _status, {
                          'all': 'All', 'in_progress': 'Active', 'on_hold': 'On Hold', 'completed': 'Done',
                        }, (v) => setState(() => _status = v),),
                        if (employees.isNotEmpty)
                          _filterChip('Employee', _employee ?? 'all',
                              {'all': 'All', ...employees}, (v) => setState(() => _employee = v == 'all' ? null : v),),
                        if (clients.isNotEmpty)
                          _filterChip('Client', _client ?? 'all',
                              {'all': 'All', ...clients}, (v) => setState(() => _client = v == 'all' ? null : v),),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty)
                      const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No team logs match.')))
                    else
                      for (final l in list) _LogCard(log: l, showEmployee: true),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value, Map<String, String> opts, ValueChanged<String> onChanged) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      itemBuilder: (_) => [for (final e in opts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      child: Chip(
        label: Text('$label: ${opts[value] ?? value}'),
        avatar: const Icon(Icons.filter_list, size: 16),
      ),
    );
  }
}

// ── Report ──────────────────────────────────────────────
class _ReportView extends ConsumerWidget {
  const _ReportView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(logReportFilterProvider);
    final async = ref.watch(logReportProvider);
    final ctrl = ref.read(logReportFilterProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 16),
                label: Text('${filter.start} → ${filter.end}', style: const TextStyle(fontSize: 12)),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(DateTime.now().year - 2),
                    lastDate: DateTime(DateTime.now().year + 1),
                    initialDateRange: DateTimeRange(start: DateTime.parse(filter.start), end: DateTime.parse(filter.end)),
                  );
                  if (picked != null) {
                    String f(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                    ctrl.state = filter.copyWith(start: f(picked.start), end: f(picked.end));
                  }
                },
              ),),
              IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: () => _exportReport(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(logReportProvider);
              await ref.read(logReportProvider.future);
            },
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
              data: (logs) {
                final totalMin = logs.fold<int>(0, (a, l) => a + l.timeSpentMinutes);
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _stat(context, '${logs.length}', 'Entries'),
                            _stat(context, formatMinutes(totalMin), 'Total time'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (logs.isEmpty)
                      const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No logs in this range.')))
                    else
                      for (final l in logs) _LogCard(log: l, showEmployee: true, showDate: true),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String v, String l) => Column(
        children: [
          Text(v, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text(l, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final logs = ref.read(logReportProvider).valueOrNull ?? const [];
    if (logs.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Nothing to export.')));
      return;
    }
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    final rows = <String>[
      'Date,Employee,Department,Client,Client ID,Description,Time Spent,Hours,Start,End,Status,Notes',
      for (final l in logs)
        [
          q(l.logDate), q(l.employeeName), q(departmentLabel(l.department)),
          q(l.clientName), q(l.clientCode), q(l.taskDescription),
          q(formatMinutes(l.timeSpentMinutes)),
          (l.timeSpentMinutes / 60).toStringAsFixed(2),
          q(l.startTime), q(l.endTime), q(l.statusLabel), q(l.notes),
        ].join(','),
    ];
    await _share('work-logs-report', '\u{FEFF}${rows.join('\n')}', messenger);
  }
}

Future<void> _share(String name, String csv, ScaffoldMessengerState messenger) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: name);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

// ── Shared log card ─────────────────────────────────────
class _LogCard extends ConsumerWidget {
  const _LogCard({
    required this.log,
    this.editable = false,
    this.showEmployee = false,
    this.showDate = false,
  });
  final WorkLog log;
  final bool editable;
  final bool showEmployee;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(logSheetRepositoryProvider);
    void refresh() {
      ref.invalidate(myLogsProvider);
      ref.invalidate(teamLogsProvider);
      ref.invalidate(liveLogsProvider);
    }

    Future<void> run(Future<void> Function() f) async {
      final m = ScaffoldMessenger.of(context);
      try {
        await f();
        refresh();
      } catch (e) {
        m.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(log.taskDescription, style: const TextStyle(fontWeight: FontWeight.bold))),
                _StatusChip(status: log.status),
              ],
            ),
            const SizedBox(height: 4),
            if (showEmployee && log.employeeName != null)
              Text(log.employeeName!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 12,
              children: [
                if (showDate) _meta(theme, Icons.event, log.logDate),
                if (log.clientName != null) _meta(theme, Icons.business, log.clientCode != null ? '${log.clientName} (${log.clientCode})' : log.clientName!),
                if (log.department != null) _meta(theme, Icons.category_outlined, departmentLabel(log.department)),
                _meta(theme, Icons.timer_outlined, formatMinutes(log.timeSpentMinutes)),
                if (log.startTime != null)
                  _meta(theme, Icons.schedule, '${log.startTime}${log.endTime != null ? ' – ${log.endTime}' : ''}'),
              ],
            ),
            if (log.notes != null && log.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(log.notes!, style: theme.textTheme.bodySmall),
              ),
            if (editable) ...[
              const Divider(height: 16),
              Wrap(
                spacing: 4,
                children: [
                  if (log.isActive) ...[
                    _act(Icons.pause, 'Pause', () => run(() => repo.pauseLog(log))),
                    _act(Icons.check, 'Complete', () => run(() => repo.completeLog(log))),
                  ] else if (log.isOnHold)
                    _act(Icons.play_arrow, 'Resume', () => run(() => repo.resumeLog(log))),
                  _act(Icons.edit_outlined, 'Edit', () => showLogEntrySheet(context, logDate: log.logDate, existing: log)),
                  _act(Icons.history, 'History', () => showLogHistoryDialog(context, ref, log)),
                  _act(Icons.delete_outline, 'Delete', () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete entry?'),
                        content: const Text('This permanently deletes the log entry.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) run(() => repo.deleteLog(log.id));
                  }, danger: true,),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _act(IconData icon, String label, VoidCallback onTap, {bool danger = false}) =>
      TextButton.icon(
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: danger ? TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)) : null,
        onPressed: onTap,
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String? status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      'in_progress' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A), 'Active'),
      'on_hold' => (const Color(0xFFFEF3C7), const Color(0xFFD97706), 'On Hold'),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280), 'Done'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
