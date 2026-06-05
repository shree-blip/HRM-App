import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/attendance_time.dart';
import '../data/attendance_providers.dart';
import '../data/live_attendance.dart';
import 'widgets/live_status_style.dart';

/// Full attendance activity timeline — ports the web "Full Recent Activity"
/// dialog: NPT/PST clocks, search, date-range, employee + type filters.
class FullActivityScreen extends ConsumerStatefulWidget {
  const FullActivityScreen({super.key});

  @override
  ConsumerState<FullActivityScreen> createState() => _FullActivityScreenState();
}

class _FullActivityScreenState extends ConsumerState<FullActivityScreen> {
  Timer? _clock;
  String _npt = '';
  String _pt = '';
  String _search = '';
  String _range = 'today'; // today | last3 | week | month
  String _employee = 'all';
  String _type = 'all';

  static const _types = ['all', 'IN', 'BRS', 'BRE', 'PAUSE', 'CONT', 'OUT'];

  @override
  void initState() {
    super.initState();
    _tick();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _tick() {
    final utc = DateTime.now().toUtc();
    final npt = utc.add(NptTime.offset);
    // Pacific: rough DST (Apr–Oct => -7, else -8) for display.
    final isDst = utc.month >= 4 && utc.month <= 10;
    final pt = utc.subtract(Duration(hours: isDst ? 7 : 8));
    setState(() {
      _npt = _hm(npt);
      _pt = _hm(pt);
    });
  }

  String _hm(DateTime d) {
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  DateTime _rangeStart() {
    final now = DateTime.now().toUtc();
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    return switch (_range) {
      'last3' => dayStart.subtract(const Duration(days: 2)),
      'week' => dayStart.subtract(Duration(days: now.weekday - 1)),
      'month' => DateTime.utc(now.year, now.month, 1),
      _ => dayStart,
    };
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(fullActivityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Full Activity')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load activity.')),
        data: (all) => _body(context, all),
      ),
    );
  }

  Widget _body(BuildContext context, List<LiveEvent> all) {
    final start = _rangeStart();
    final q = _search.trim().toLowerCase();

    // Base set = date + employee + search (type counts computed off this).
    final base = all.where((e) {
      if (e.time.isBefore(start)) return false;
      if (_employee != 'all' && e.name != _employee) return false;
      if (q.isNotEmpty) {
        final hay =
            '${e.name} ${e.department ?? ''} ${LiveStatusStyle.of(e.type).label}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    final counts = {for (final t in _types) t: 0};
    counts['all'] = base.length;
    for (final e in base) {
      counts[e.type] = (counts[e.type] ?? 0) + 1;
    }

    final filtered =
        base.where((e) => _type == 'all' || e.type == _type).toList();

    final employees = {for (final e in all) e.name}.toList()..sort();

    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  _clockChip(context, 'Nepal', _npt),
                  const SizedBox(width: 8),
                  _clockChip(context, 'Pacific', _pt),
                  const SizedBox(width: 8),
                  _clockChip(context, 'Events', '${base.length}'),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search employee, dept…',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _dropdown(
                      _range,
                      const {
                        'today': 'Today',
                        'last3': 'Last 3 Days',
                        'week': 'This Week',
                        'month': 'This Month',
                      },
                      (v) => setState(() => _range = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _dropdown(
                      _employee,
                      {'all': 'All Employees', for (final n in employees) n: n},
                      (v) => setState(() => _employee = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in _types)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                              '${t == 'all' ? 'All' : LiveStatusStyle.of(t).label} ${counts[t] ?? 0}',),
                          selected: _type == t,
                          onSelected: (_) => setState(() => _type = t),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Showing ${filtered.length} of ${base.length} activities',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No activity matches the filters'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _row(context, filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _clockChip(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600),),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) {
    return InputDecorator(
      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [
            for (final e in options.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => onChanged(v ?? value),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, LiveEvent e) {
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: style.bg,
                          borderRadius: BorderRadius.circular(6),),
                      child: Text(style.label,
                          style: TextStyle(fontSize: 10, color: style.color),),
                    ),
                  ],
                ),
                Text(
                  '${e.department ?? 'No Dept'} • ${formatDateTimeLong(e.time)}',
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
}
