import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../../core/utils/attendance_time.dart';
import '../data/reports_models.dart';
import '../data/reports_providers.dart';
import 'edit_attendance_screen.dart';

/// Reports & Attendance Summary (Phase 7). Tabs: Summary (per-employee) and
/// Daily (employee-wise records). Date-range + employee filters + CSV export.
/// Data is RLS-scoped (VP/Admin org-wide, managers their team).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportDataProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Export CSV',
              icon: const Icon(Icons.file_download_outlined),
              onSelected: (v) => _export(context, ref, v),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  enabled: false,
                  child: Text('Export CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                PopupMenuItem(value: 'summary', child: Text('Attendance summary')),
                PopupMenuItem(value: 'daily', child: Text('Daily attendance')),
              ],
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(reportDataProvider),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Summary'), Tab(text: 'Daily')],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/reports'),
        body: Column(
          children: [
            const _FilterBar(),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Could not load report.\n$e',
                    textAlign: TextAlign.center,),),
                data: (data) => TabBarView(
                  children: [
                    _SummaryTab(data: data),
                    _DailyTab(data: data),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref, String which) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = ref.read(reportDataProvider).valueOrNull;
    if (data == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Report still loading…')));
      return;
    }
    final emp = ref.read(reportEmployeeProvider);
    final repo = ref.read(reportsRepositoryProvider);
    try {
      final String csv, name;
      if (which == 'summary') {
        csv = repo.summaryCsv(data);
        name = 'attendance-summary';
      } else {
        final daily = emp == 'all'
            ? data.daily
            : data.daily.where((r) => r.userId == emp).toList();
        csv = repo.dailyCsv(daily);
        name = 'daily-attendance';
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
          subject: name,);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(reportRangeProvider.notifier);
    final range = ref.watch(reportRangeProvider);
    final selectedRange = ctrl.range;
    final data = ref.watch(reportDataProvider).valueOrNull;
    final selectedEmp = ref.watch(reportEmployeeProvider);

    final employees = <String, String>{
      'all': 'All employees',
      if (data != null)
        for (final s in data.summaries) s.userId: s.name,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _dropdown<ReportRange>(
                  context,
                  label: 'Range',
                  value: selectedRange == ReportRange.custom ? null : selectedRange,
                  hint: selectedRange == ReportRange.custom ? range.label : null,
                  items: {
                    for (final r in ReportRange.values)
                      if (r != ReportRange.custom) r: r.label,
                  },
                  onChanged: (r) => ctrl.setPreset(r),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: const Text('Custom'),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(DateTime.now().year - 2),
                    lastDate: DateTime(DateTime.now().year + 1),
                  );
                  if (picked != null) ctrl.setCustom(picked.start, picked.end);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _dropdown<String>(
            context,
            label: 'Employee',
            value: employees.containsKey(selectedEmp) ? selectedEmp : 'all',
            items: employees,
            onChanged: (v) => ref.read(reportEmployeeProvider.notifier).state = v,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${range.label}'
              '${data != null ? '  ·  ${data.workingDays} working days  ·  target ${data.targetHours.toInt()}h' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required String label,
    required T? value,
    String? hint,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: hint != null ? Text(hint) : null,
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final emp = ref.watch(reportEmployeeProvider);
    final rows = emp == 'all'
        ? data.summaries
        : data.summaries.where((s) => s.userId == emp).toList();

    final totalDays = rows.fold<double>(0, (s, r) => s + r.effectiveDaysWorked);
    final totalHours = rows.fold<double>(0, (s, r) => s + r.totalHours);
    final avg = rows.isEmpty ? 0.0 : totalHours / rows.length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            _stat(theme, 'Employees', '${rows.length}'),
            _stat(theme, 'Avg hrs', avg.toStringAsFixed(1)),
            _stat(theme, 'Days worked', _n(totalDays)),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No attendance in this period.')),
          )
        else
          for (final s in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (s.email.isNotEmpty)
                      Text(s.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,),),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _kv(theme, 'Days worked', _n(s.effectiveDaysWorked)),
                        _kv(theme, 'Total hours', '${_n(s.totalHours)}h'),
                      ],
                    ),
                    if (s.deductionType != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Leave — paid: ${_n(s.paidLeaveDays)}, payroll: ${_n(s.payrollLeaveDays)}  ·  ${s.deductionType}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stat(ThemeData theme, String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),),
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            ],
          ),
        ),
      );

  Widget _kv(ThemeData theme, String k, String v) => Expanded(
        child: RichText(
          text: TextSpan(style: theme.textTheme.bodyMedium, children: [
            TextSpan(
                text: '$k: ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),),
            TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],),
        ),
      );
}

class _DailyTab extends ConsumerWidget {
  const _DailyTab({required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emp = ref.watch(reportEmployeeProvider);
    final perms = ref.watch(permissionsControllerProvider);
    final isVp = ref.watch(authControllerProvider.select((s) => s.isVp));
    final canEdit = isVp || perms.has(Permission.editAttendance);
    final rows = emp == 'all'
        ? data.daily
        : data.daily.where((r) => r.userId == emp).toList();
    if (rows.isEmpty) {
      return const Center(child: Text('No daily records in this period.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      itemBuilder: (_, i) => _DailyCard(record: rows[i], canEdit: canEdit),
    );
  }
}

/// One daily attendance row — expandable to show each break/pause session
/// (type, start → end, duration), mirroring the web BreakPauseDetailPanel.
class _DailyCard extends ConsumerStatefulWidget {
  const _DailyCard({required this.record, required this.canEdit});
  final DailyRecord record;
  final bool canEdit;
  @override
  ConsumerState<_DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends ConsumerState<_DailyCard> {
  bool _expanded = false;
  bool _loading = false;
  List<({String dbId, String type, DateTime start, DateTime? end})>? _sessions;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _sessions == null && !_loading) {
      setState(() => _loading = true);
      try {
        final rows =
            await ref.read(reportsRepositoryProvider).sessions(widget.record.id);
        if (mounted) setState(() => _sessions = rows);
      } catch (_) {
        if (mounted) setState(() => _sessions = const []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  String _dur(DateTime start, DateTime? end) {
    final e = end ?? DateTime.now().toUtc();
    final m = e.difference(start).inMinutes;
    if (m <= 0) return '0m';
    final h = m ~/ 60;
    return h == 0 ? '${m}m' : '${h}h ${m % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.record;
    final hasBreakOrPause = r.breakMinutes > 0 || r.pauseMinutes > 0;
    return Card(
      child: InkWell(
        onTap: hasBreakOrPause ? _toggle : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${r.name} · ${r.dateKey}',
                        style: const TextStyle(fontWeight: FontWeight.w600),),
                  ),
                  _StatusChip(status: r.status),
                  if (widget.canEdit)
                    IconButton(
                      tooltip: 'Edit attendance',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditAttendanceScreen(record: r),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${NptTime.formatTime(r.clockIn)} → '
                '${r.clockOut != null ? NptTime.formatTime(r.clockOut!) : 'now'}'
                '  ·  ${_n(r.netHours)}h net',
                style: theme.textTheme.bodySmall,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Break ${r.breakMinutes}m · Pause ${r.pauseMinutes}m'
                      '${r.isEdited ? ' · edited' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,),
                    ),
                  ),
                  if (hasBreakOrPause)
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: theme.colorScheme.onSurfaceVariant,),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 16),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),),
                    ),
                  )
                else if ((_sessions ?? const []).isEmpty)
                  // Legacy rows have totals only — show synthetic entries.
                  Column(children: [
                    if (r.breakMinutes > 0)
                      _sessionTile(context, 'break', null, null, '${r.breakMinutes}m'),
                    if (r.pauseMinutes > 0)
                      _sessionTile(context, 'pause', null, null, '${r.pauseMinutes}m'),
                  ],)
                else
                  Column(children: [
                    for (final s in _sessions!)
                      _sessionTile(context, s.type, s.start, s.end, _dur(s.start, s.end)),
                  ],),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(BuildContext context, String type, DateTime? start,
      DateTime? end, String duration,) {
    final theme = Theme.of(context);
    final isBreak = type == 'break';
    final color = isBreak ? Colors.orange.shade800 : Colors.blue.shade700;
    final times = start != null
        ? '${NptTime.formatTime(start)} → ${end != null ? NptTime.formatTime(end) : 'ongoing'}'
        : 'no session detail';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(isBreak ? Icons.coffee_outlined : Icons.pause_circle_outline,
            size: 16, color: color,),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(isBreak ? 'Break' : 'Pause',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color,),),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(times, style: theme.textTheme.bodySmall)),
        Text(duration,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),),
      ],),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'Overtime' => (const Color(0xFFE0E7FF), const Color(0xFF4F46E5)),
      'Complete' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'Short' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),),
    );
  }
}

String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
