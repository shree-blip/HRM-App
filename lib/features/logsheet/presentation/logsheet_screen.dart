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
    // Live-sync work_logs changes (e.g. pause/resume done on the web app).
    ref.watch(logSheetRealtimeProvider);

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
class _MyLogView extends ConsumerStatefulWidget {
  const _MyLogView();
  @override
  ConsumerState<_MyLogView> createState() => _MyLogViewState();
}

class _MyLogViewState extends ConsumerState<_MyLogView> {
  String _status = 'all'; // all | in_progress | on_hold | completed

  @override
  Widget build(BuildContext context) {
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
              data: (logs) {
                // Summary reflects the whole day (web: totals computed over all
                // logs, not the filtered subset).
                final totalMin = logs.fold<int>(0, (a, l) => a + l.timeSpentMinutes);
                final inProgress = logs.where((l) => l.status == 'in_progress').length;
                final completed = logs.where((l) => l.status == 'completed').length;
                final filtered =
                    _status == 'all' ? logs : logs.where((l) => l.status == _status).toList();
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _SummaryCards(
                      total: logs.length,
                      totalTime: formatMinutes(totalMin),
                      inProgress: inProgress,
                      completed: completed,
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final e in const {
                          'all': 'All',
                          'in_progress': 'Active',
                          'on_hold': 'On Hold',
                          'completed': 'Done',
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: _status == e.key,
                              onSelected: (_) => setState(() => _status = e.key),
                            ),
                          ),
                      ],),
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text('No log entries for this day.')),
                      )
                    else
                      for (final l in filtered) _LogCard(log: l, editable: true),
                  ],
                );
              },
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

/// Day summary cards for My Log (web parity: Total Logs, Total Time,
/// In Progress, Completed).
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.total,
    required this.totalTime,
    required this.inProgress,
    required this.completed,
  });
  final int total;
  final String totalTime;
  final int inProgress;
  final int completed;

  @override
  Widget build(BuildContext context) {
    Widget card(IconData icon, String value, String label, Color color) => Expanded(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(height: 4),
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis,),
                  Text(label,
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,),
                ],
              ),
            ),
          ),
        );

    return Row(
      children: [
        card(Icons.list_alt, '$total', 'Total Logs', const Color(0xFF1FA8C9)),
        card(Icons.timer_outlined, totalTime, 'Total Time', const Color(0xFF0D6B82)),
        card(Icons.play_circle_outline, '$inProgress', 'In Progress', const Color(0xFFD97706)),
        card(Icons.check_circle_outline, '$completed', 'Completed', const Color(0xFF16A34A)),
      ],
    );
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
                    // One clean horizontal scroll row — the Client chip used
                    // to wrap onto a second line.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip('Status', _status, {
                            'all': 'All', 'in_progress': 'Active', 'on_hold': 'On Hold', 'completed': 'Done',
                          }, (v) => setState(() => _status = v),),
                          const SizedBox(width: 8),
                          if (employees.isNotEmpty) ...[
                            _filterChip('Employee', _employee ?? 'all',
                                {'all': 'All', ...employees}, (v) => setState(() => _employee = v == 'all' ? null : v),),
                            const SizedBox(width: 8),
                          ],
                          if (clients.isNotEmpty)
                            _filterChip('Client', _client ?? 'all',
                                {'all': 'All', ...clients}, (v) => setState(() => _client = v == 'all' ? null : v),),
                        ],
                      ),
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
// A time-by-X breakdown row.
class _Breakdown {
  _Breakdown(this.label, {this.sub}) : minutes = 0;
  final String label;
  final String? sub;
  int minutes;
}

({List<_Breakdown> clients, List<_Breakdown> employees, List<_Breakdown> depts})
    _summaries(List<WorkLog> logs) {
  final clients = <String, _Breakdown>{};
  final employees = <String, _Breakdown>{};
  final depts = <String, _Breakdown>{};
  for (final l in logs) {
    final cName = l.clientName ?? 'No Client';
    (clients[cName] ??= _Breakdown(cName, sub: l.clientCode)).minutes += l.timeSpentMinutes;
    final eName = l.employeeName ?? 'Unassigned';
    final eDept = departmentLabel(l.department ?? l.employeeDept);
    (employees[eName] ??= _Breakdown(eName, sub: eDept)).minutes += l.timeSpentMinutes;
    final dRaw = l.department ?? 'No Department';
    (depts[dRaw] ??= _Breakdown(departmentLabel(l.department))).minutes += l.timeSpentMinutes;
  }
  List<_Breakdown> sorted(Map<String, _Breakdown> m) =>
      m.values.toList()..sort((a, b) => b.minutes.compareTo(a.minutes));
  return (clients: sorted(clients), employees: sorted(employees), depts: sorted(depts));
}

class _ReportView extends ConsumerWidget {
  const _ReportView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final draft = ref.watch(logReportDraftProvider);
    final applied = ref.watch(appliedReportProvider);
    final async = ref.watch(logReportProvider);
    final clients = ref.watch(clientsProvider).valueOrNull ?? const [];
    final employees = ref.watch(reportEmployeesProvider).valueOrNull ?? const [];
    final ctrl = ref.read(logReportDraftProvider.notifier);

    final clientName = draft.clientId == null
        ? 'All clients'
        : clients.firstWhere((c) => c.id == draft.clientId,
            orElse: () => const Client(id: '', name: '—'),).display;
    final empName = draft.employeeId == null
        ? 'All employees'
        : employees.firstWhere((e) => e.id == draft.employeeId,
            orElse: () => const LogEmployee(id: '', name: '—'),).display;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Filters ──
        _FilterTile(
          icon: Icons.business,
          label: 'Client',
          value: clientName,
          onClear: draft.clientId == null ? null : () => ctrl.state = draft.copyWith(clientId: null),
          onTap: () async {
            final v = await _pick(context, 'Select client', [
              (value: null, label: 'All clients', sub: null),
              for (final c in clients) (value: c.id, label: c.name, sub: c.code),
            ], draft.clientId,);
            ctrl.state = draft.copyWith(clientId: v);
          },
        ),
        _FilterTile(
          icon: Icons.person_outline,
          label: 'Employee',
          value: empName,
          onClear: draft.employeeId == null ? null : () => ctrl.state = draft.copyWith(employeeId: null),
          onTap: () async {
            final v = await _pick(context, 'Select employee', [
              (value: null, label: 'All employees', sub: null),
              for (final e in employees) (value: e.id, label: e.name, sub: e.employeeId ?? e.email),
            ], draft.employeeId,);
            ctrl.state = draft.copyWith(employeeId: v);
          },
        ),
        _FilterTile(
          icon: Icons.category_outlined,
          label: 'Task Department',
          value: draft.department == null ? 'All task departments' : departmentLabel(draft.department),
          onClear: draft.department == null ? null : () => ctrl.state = draft.copyWith(department: null),
          onTap: () async {
            final v = await _pick(context, 'Select task department', [
              (value: null, label: 'All task departments', sub: null),
              for (final o in kDepartmentOptions) (value: o.value, label: o.label, sub: null),
            ], draft.department,);
            ctrl.state = draft.copyWith(department: v);
          },
        ),
        _FilterTile(
          icon: Icons.date_range,
          label: 'Date range',
          value: '${draft.start} → ${draft.end}',
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(DateTime.now().year - 2),
              lastDate: DateTime(DateTime.now().year + 1),
              initialDateRange: DateTimeRange(start: DateTime.parse(draft.start), end: DateTime.parse(draft.end)),
            );
            if (picked != null) {
              String f(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              ctrl.state = draft.copyWith(start: f(picked.start), end: f(picked.end));
            }
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.assessment_outlined, size: 18),
          label: const Text('Generate Report'),
          onPressed: () => ref.read(appliedReportProvider.notifier).state = draft,
        ),
        const Divider(height: 24),

        // ── Results ──
        if (applied == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Set filters and tap Generate Report.')),
          )
        else
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e')),
            data: (logs) {
              if (logs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('No logs found for the selected filters in the date range.')),
                );
              }
              final totalMin = logs.fold<int>(0, (a, l) => a + l.timeSpentMinutes);
              final s = _summaries(logs);
              final typeLabel = _reportTypeLabel(applied);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary bar
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Chip(
                                label: Text('$typeLabel Report'),
                                backgroundColor: applied.clientId == null && applied.employeeId == null && applied.department == null
                                    ? theme.colorScheme.primaryContainer
                                    : null,
                                visualDensity: VisualDensity.compact,
                              ),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text('CSV'),
                                onPressed: () => _exportReport(context, ref, applied, logs, s,
                                    clients, employees,),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 20,
                            runSpacing: 10,
                            children: [
                              if (applied.clientId == null) _stat(context, '${s.clients.length}', 'Total Clients'),
                              if (applied.employeeId == null) _stat(context, '${s.employees.length}', 'Total Employees'),
                              _stat(context, '${logs.length}', 'Total Entries'),
                              _stat(context, formatMinutes(totalMin), 'Total Time'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (applied.clientId == null)
                    _breakdownSection(context, Icons.business, 'Time by Client', s.clients),
                  if (applied.employeeId == null)
                    _breakdownSection(context, Icons.person_outline, 'Time by Employee', s.employees),
                  if (applied.department == null)
                    _breakdownSection(context, Icons.apartment, 'Time by Department', s.depts),
                  const SizedBox(height: 6),
                  Text('Detailed entries',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),),
                  const SizedBox(height: 6),
                  for (final l in logs.take(15)) _LogCard(log: l, showEmployee: true, showDate: true),
                  if (logs.length > 15)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: Text('Showing 15 of ${logs.length} entries. Download CSV for the full report.',
                            style: theme.textTheme.bodySmall,),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _stat(BuildContext context, String v, String l) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l, style: Theme.of(context).textTheme.bodySmall),
          Text(v, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      );

  Widget _breakdownSection(BuildContext context, IconData icon, String title, List<_Breakdown> items) =>
      _BreakdownCard(icon: icon, title: title, items: items);

  String _reportTypeLabel(ReportFilter f) {
    final parts = <String>[];
    if (f.clientId != null) parts.add('Client');
    if (f.employeeId != null) parts.add('Employee');
    if (f.department != null) parts.add('Department');
    return parts.isEmpty ? 'All Data' : parts.join(' & ');
  }

  Future<void> _exportReport(
    BuildContext context,
    WidgetRef ref,
    ReportFilter f,
    List<WorkLog> logs,
    ({List<_Breakdown> clients, List<_Breakdown> employees, List<_Breakdown> depts}) s,
    List<Client> clients,
    List<LogEmployee> employees,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    String t(int m) => formatMinutes(m);
    String dec(int m) => (m / 60).toStringAsFixed(2);
    String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final totalMin = logs.fold<int>(0, (a, l) => a + l.timeSpentMinutes);

    final clientObj = f.clientId == null ? null : clients.firstWhere((c) => c.id == f.clientId, orElse: () => const Client(id: '', name: ''));
    final empObj = f.employeeId == null ? null : employees.firstWhere((e) => e.id == f.employeeId, orElse: () => const LogEmployee(id: '', name: ''));
    final isAll = f.clientId == null && f.employeeId == null && f.department == null;

    final n = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 45));
    String pad(int x) => x.toString().padLeft(2, '0');
    final genOn = '${n.year}-${pad(n.month)}-${pad(n.day)} ${pad(n.hour)}:${pad(n.minute)}';

    final lines = <String>[];
    lines.add(isAll ? 'COMPLETE WORK LOG REPORT - ALL CLIENTS & EMPLOYEES' : 'WORK LOG REPORT');
    lines.add('');
    if (clientObj != null) {
      lines.add('Client Name,${q(clientObj.name)}');
      if ((clientObj.code ?? '').isNotEmpty) lines.add('Client ID,${q(clientObj.code)}');
    } else {
      lines.add('Client Filter,All Clients');
    }
    if (empObj != null) {
      lines.add('Employee Name,${q(empObj.name)}');
      if ((empObj.employeeId ?? '').isNotEmpty) lines.add('Employee ID,${q(empObj.employeeId)}');
    } else {
      lines.add('Employee Filter,All Employees');
    }
    lines.add(f.department != null
        ? 'Task Department Filter,${q(departmentLabel(f.department))}'
        : 'Task Department Filter,All Task Departments',);
    lines.add('Report Period,${f.start} to ${f.end}');
    lines.add('Generated On,$genOn');
    lines.add('');

    lines.add('SUMMARY');
    lines.add('');
    lines.add('Total Entries,${logs.length}');
    lines.add('Total Time,${t(totalMin)} (${dec(totalMin)} hours)');
    if (f.clientId == null) lines.add('Total Clients,${s.clients.length}');
    if (f.employeeId == null) lines.add('Total Employees,${s.employees.length}');
    if (f.department == null) lines.add('Total Task Departments,${s.depts.length}');
    lines.add('');

    if (f.clientId == null && s.clients.isNotEmpty) {
      lines.add('TIME BY CLIENT');
      lines.add('');
      lines.add('Client Name,Client ID,Total Time,Hours (Decimal)');
      for (final c in s.clients) {
        lines.add('${q(c.label)},${q(c.sub ?? 'N/A')},${q(t(c.minutes))},${dec(c.minutes)}');
      }
      lines.add('${q('TOTAL')},"",${q(t(totalMin))},${dec(totalMin)}');
      lines.add('');
    }
    if (f.employeeId == null && s.employees.isNotEmpty) {
      lines.add('TIME BY EMPLOYEE');
      lines.add('');
      lines.add('Employee Name,Department,Total Time,Hours (Decimal)');
      for (final e in s.employees) {
        lines.add('${q(e.label)},${q(e.sub)},${q(t(e.minutes))},${dec(e.minutes)}');
      }
      lines.add('${q('TOTAL')},"",${q(t(totalMin))},${dec(totalMin)}');
      lines.add('');
    }
    if (f.department == null && s.depts.isNotEmpty) {
      lines.add('TIME BY TASK DEPARTMENT');
      lines.add('');
      lines.add('Task Department,Total Time,Hours (Decimal)');
      for (final d in s.depts) {
        lines.add('${q(d.label)},${q(t(d.minutes))},${dec(d.minutes)}');
      }
      lines.add('${q('TOTAL')},${q(t(totalMin))},${dec(totalMin)}');
      lines.add('');
    }

    lines.add('DETAILED LOG ENTRIES');
    lines.add('');
    lines.add('Date,Employee,Department,Task Department,Client,Client ID,Description,Time Spent,Hours (Decimal),Start Time,End Time,Status,Notes');
    for (final l in logs) {
      lines.add([
        q(l.logDate),
        q(l.employeeName ?? 'N/A'),
        q(l.employeeDept ?? 'N/A'),
        q(l.department != null ? departmentLabel(l.department) : 'N/A'),
        q(l.clientName ?? 'N/A'),
        q(l.clientCode ?? 'N/A'),
        q(l.taskDescription),
        q(t(l.timeSpentMinutes)),
        dec(l.timeSpentMinutes),
        q(l.startTime),
        q(l.endTime),
        q(l.status ?? 'completed'),
        q(l.notes),
      ].join(','),);
    }

    // Filename based on filters.
    var name = 'work_logs';
    if (clientObj != null) {
      name += '_${clientObj.name.replaceAll(RegExp(r"\s+"), "_")}';
      if ((clientObj.code ?? '').isNotEmpty) name += '_${clientObj.code}';
    } else {
      name += '_all_clients';
    }
    if (empObj != null) {
      name += '_${empObj.name.replaceAll(RegExp(r"\s+"), "_")}';
      if ((empObj.employeeId ?? '').isNotEmpty) name += '_${empObj.employeeId}';
    } else {
      name += '_all_employees';
    }
    if (f.department != null) {
      name += '_${departmentLabel(f.department).replaceAll(RegExp(r"[→\s]+"), "_")}';
    }
    name += '_${f.start}_to_${f.end}';

    await _share(name, '\u{FEFF}${lines.join('\n')}', messenger);
  }
}

/// One "Time by …" card: shows the first 5 rows with a Show more / Show less
/// toggle (long reports needed too much scrolling). CSV export is unchanged.
class _BreakdownCard extends StatefulWidget {
  const _BreakdownCard({required this.icon, required this.title, required this.items});
  final IconData icon;
  final String title;
  final List<_Breakdown> items;

  @override
  State<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends State<_BreakdownCard> {
  static const _preview = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final visible = _expanded ? items : items.take(_preview).toList();
    final hiddenCount = items.length - _preview;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(widget.icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('${widget.title} (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],),
            const SizedBox(height: 8),
            ...visible.map((b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                            if (b.sub != null && b.sub!.isNotEmpty)
                              Text(b.sub!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(formatMinutes(b.minutes),
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSecondaryContainer),),
                      ),
                    ],
                  ),
                ),),
            if (hiddenCount > 0)
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
                  label: Text(_expanded ? 'Show less' : 'Show more ($hiddenCount more)'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ),
          ],
        ),
      ),
    );
  }

}

// ── Searchable picker ───────────────────────────────────
Future<String?> _pick(
  BuildContext context,
  String title,
  List<({String? value, String label, String? sub})> items,
  String? current,
) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(title: title, items: items, current: current),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.items, this.current});
  final String title;
  final List<({String? value, String label, String? sub})> items;
  final String? current;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((i) {
      if (_q.isEmpty) return true;
      final hay = '${i.label} ${i.sub ?? ''}'.toLowerCase();
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
                  Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search…',
                    ),
                    onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final item = filtered[i];
                  final selected = item.value == widget.current;
                  return ListTile(
                    dense: true,
                    leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18, color: selected ? Theme.of(context).colorScheme.primary : null,),
                    title: Text(item.label),
                    subtitle: item.sub != null && item.sub!.isNotEmpty ? Text(item.sub!) : null,
                    onTap: () => Navigator.pop(context, item.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter tile ─────────────────────────────────────────
class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            prefixIcon: Icon(icon, size: 18),
            suffixIcon: onClear != null
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClear)
                : const Icon(Icons.expand_more, size: 18),
          ),
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,),
        ),
      ),
    );
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
                // Pause total (web: "⏸ Xm paused"); while on hold, include
                // the ongoing pause so the total is live.
                if (log.totalPauseMinutes > 0 ||
                    (log.isOnHold && log.pauseStart != null))
                  _meta(
                    theme,
                    Icons.pause_circle_outline,
                    '${formatMinutes(log.totalPauseMinutes + ((log.isOnHold && log.pauseStart != null) ? DateTime.now().toUtc().difference(log.pauseStart!).inMinutes.clamp(0, 1 << 31) : 0))} paused',
                  ),
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
