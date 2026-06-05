import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/attendance_time.dart';
import '../../data/attendance_providers.dart';
import '../../data/live_attendance.dart';
import '../attendance_export.dart';
import '../full_activity_screen.dart';
import 'live_status_style.dart';

/// Live Attendance — ports the web RealTimeAttendanceWidget: clickable summary
/// (Total/Working/Break/Paused/Out), filtered employee list, WFO/WFH filters,
/// recent activity feed, CSV export, and a full-timeline view. Auto-refreshes
/// via realtime + 60s poll.
class LiveAttendanceCard extends ConsumerStatefulWidget {
  const LiveAttendanceCard({super.key});

  @override
  ConsumerState<LiveAttendanceCard> createState() => _LiveAttendanceCardState();
}

class _LiveAttendanceCardState extends ConsumerState<LiveAttendanceCard> {
  String? _filter; // working | break | paused | out | all | wfo | wfh

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(liveAttendanceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context),
            const SizedBox(height: 12),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Could not load live attendance.'),
              ),
              data: (d) => _content(context, d),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.timeline, size: 18),
                label: const Text('View full timeline'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FullActivityScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.bolt, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text('Live Attendance',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: Color(0xFF059669)),
              SizedBox(width: 4),
              Text('Live',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF059669),),),
            ],
          ),
        ),
        const Spacer(),
        _ExportButton(
          onSelected: (v) => exportAttendanceCsv(context, ref, v),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Refresh',
          onPressed: () => ref.read(liveAttendanceProvider.notifier).refresh(),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, LiveData d) {
    final wfoCount = d.employees
        .where((e) => e.status == 'IN' && e.workMode != 'wfh')
        .length;
    final wfhCount = d.employees
        .where((e) =>
            {'IN', 'BRS', 'PAUSE'}.contains(e.status) && e.workMode == 'wfh',)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _summaryCell('all', 'Total', d.total, const Color(0xFF475569)),
            _summaryCell('working', 'Working', d.working, const Color(0xFF059669)),
            _summaryCell('break', 'Break', d.onBreak, const Color(0xFFD97706)),
            _summaryCell('paused', 'Paused', d.paused, const Color(0xFF2563EB)),
            _summaryCell('out', 'Out', d.out, const Color(0xFF64748B)),
          ],
        ),
        if (_filter != null) ...[
          const SizedBox(height: 12),
          _employeeList(context, d),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _filter == 'wfo'
                    ? OutlinedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),)
                    : null,
                icon: const Icon(Icons.business, size: 18),
                label: Text('WFO ($wfoCount)'),
                onPressed: () => _toggle('wfo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: _filter == 'wfh'
                    ? OutlinedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),)
                    : null,
                icon: const Icon(Icons.home_outlined, size: 18),
                label: Text('WFH ($wfhCount)'),
                onPressed: () => _toggle('wfh'),
              ),
            ),
          ],
        ),
        if (_filter == null) ...[
          const SizedBox(height: 12),
          _activityFeed(context, d),
        ],
      ],
    );
  }

  Widget _summaryCell(String key, String label, int value, Color color) {
    final active = _filter == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => _toggle(key),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: active ? 0.22 : 0.10),
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: color, width: 1.5) : null,
          ),
          child: Column(
            children: [
              Text('$value',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: color,),),
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),),
            ],
          ),
        ),
      ),
    );
  }

  Widget _employeeList(BuildContext context, LiveData d) {
    final theme = Theme.of(context);
    final list = d.employees.where(_matchesFilter).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(_filterLabel(_filter!),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _filter = null),
              ),
            ],
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No employees'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _employeeRow(context, list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _employeeRow(BuildContext context, LiveEmployee e) {
    final theme = Theme.of(context);
    final style = LiveStatusStyle.of(e.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            foregroundImage:
                (e.avatarUrl != null) ? NetworkImage(e.avatarUrl!) : null,
            child: Text(_initials(e.name),
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,),),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,),),
                Text(
                  '${e.department ?? 'No Dept'} • ${e.lastAction != null ? relativeFromNow(e.lastAction!) : '—'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: style.bg, borderRadius: BorderRadius.circular(20),),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, size: 12, color: style.color),
                const SizedBox(width: 4),
                Text(e.status,
                    style: TextStyle(
                        fontSize: 10,
                        color: style.color,
                        fontWeight: FontWeight.w600,),),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityFeed(BuildContext context, LiveData d) {
    final theme = Theme.of(context);
    final events = d.events.where((e) => e.name.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            const Text('Recent Activity',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No activity today')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: events.length,
                  itemBuilder: (_, i) => _eventRow(context, events[i]),
                ),
        ),
      ],
    );
  }

  Widget _eventRow(BuildContext context, LiveEvent e) {
    final theme = Theme.of(context);
    final style = LiveStatusStyle.of(e.type);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: style.bg, borderRadius: BorderRadius.circular(8),),
            child: Icon(style.icon, size: 14, color: style.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500,),),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: style.bg, borderRadius: BorderRadius.circular(6),),
                      child: Text(style.label,
                          style: TextStyle(fontSize: 10, color: style.color),),
                    ),
                  ],
                ),
                Text(
                  '${formatDateTimeLong(e.time)} • ${relativeFromNow(e.time)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────
  void _toggle(String key) => setState(() => _filter = _filter == key ? null : key);

  bool _matchesFilter(LiveEmployee e) {
    switch (_filter) {
      case 'all':
        return true;
      case 'working':
        return e.status == 'IN';
      case 'break':
        return e.status == 'BRS';
      case 'paused':
        return e.status == 'PAUSE';
      case 'out':
        return e.status == 'OUT';
      case 'wfo':
        return {'IN', 'BRS', 'PAUSE'}.contains(e.status) && e.workMode != 'wfh';
      case 'wfh':
        return {'IN', 'BRS', 'PAUSE'}.contains(e.status) && e.workMode == 'wfh';
      default:
        return true;
    }
  }

  String _filterLabel(String f) => switch (f) {
        'all' => 'All Employees',
        'working' => 'Currently Working',
        'break' => 'On Break',
        'paused' => 'Paused',
        'out' => 'Clocked Out',
        'wfo' => 'Work From Office',
        'wfh' => 'Work From Home',
        _ => 'Employees',
      };

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final f = parts.first[0];
    final l = parts.length > 1 ? parts.last[0] : '';
    return '$f$l'.toUpperCase();
  }

}

/// Clearly-visible "Export CSV ▾" chip used in the Live Attendance header.
class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Export CSV',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final t in kExportTimeframes)
          PopupMenuItem(value: t.value, child: Text(t.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text('Export',
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,),),
            Icon(Icons.arrow_drop_down, size: 18, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
