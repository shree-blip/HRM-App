import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/calendar_models.dart';
import '../data/calendar_providers.dart';

/// Company Calendar (Phase 12): month grid + selected-day details + upcoming
/// list. Add/delete custom events for managers (manage_calendar). Mirrors the
/// web dashboard calendar (hardcoded entries + calendar_events).
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month; // first of month
  DateTime? _selected;
  String _tab = 'upcoming'; // upcoming | holidays | deadlines | milestones

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
    _selected = DateTime(n.year, n.month, n.day);
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(calendarEntriesProvider);
    final canManage = canManageCalendar(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Calendar'),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Add event',
              icon: const Icon(Icons.add),
              onPressed: () => _showAddDialog(context, ref, _selected ?? DateTime.now()),
            ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/calendar'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load calendar.\n$e', textAlign: TextAlign.center)),
        data: (entries) {
          final byDay = <String, List<CalendarEntry>>{};
          for (final e in entries) {
            (byDay[e.dateKey] ??= []).add(e);
          }
          final today = DateTime.now();
          final upcoming = entries.where((e) => !e.date.isBefore(DateTime(today.year, today.month, today.day))).take(20).toList();
          final selEntries = _selected != null ? (byDay[_key(_selected!)] ?? const []) : const <CalendarEntry>[];
          // Milestones for the displayed month (grid markers + selected-day).
          final monthMilestones = _monthMilestones(
              ref.watch(milestoneProfilesProvider).valueOrNull ?? const [],);
          final milestoneDays = {for (final m in monthMilestones) m.date.day};
          final selMilestones = _selected != null &&
                  _selected!.month == _month.month &&
                  _selected!.year == _month.year
              ? monthMilestones
                  .where((m) => m.date.day == _selected!.day)
                  .toList()
              : const <({String name, String type, DateTime date, int? years})>[];

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(calendarEntriesProvider);
              await ref.read(calendarEntriesProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _monthHeader(),
                const SizedBox(height: 8),
                _grid(byDay, milestoneDays),
                const SizedBox(height: 8),
                _legend(),
                const Divider(height: 24),
                if (_selected != null) ...[
                  Text(_fmtLong(_selected!), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (selEntries.isEmpty && selMilestones.isEmpty)
                    Text('No events on this day.', style: Theme.of(context).textTheme.bodySmall)
                  else ...[
                    for (final e in selEntries) _entryTile(e, canManage),
                    // Selected-day milestones (web selectedMilestones).
                    if (selMilestones.isNotEmpty) _milestoneList(selMilestones),
                  ],
                  const Divider(height: 24),
                ],
                // Tab strip — web CompanyCalendar tabs (Upcoming / Holidays /
                // Deadlines / Milestones); month-scoped counts like the web.
                Builder(builder: (context) {
                  final monthEntries = entries
                      .where((e) =>
                          e.date.year == _month.year &&
                          e.date.month == _month.month,)
                      .toList();
                  final holidays = monthEntries
                      .where((e) => e.type == 'holiday' || e.type == 'optional')
                      .toList();
                  final deadlines = monthEntries
                      .where((e) => e.type == 'deadline' || e.type == 'event')
                      .toList();
                  final milestonesAsync = ref.watch(milestoneProfilesProvider);
                  final milestones = _monthMilestones(
                      milestonesAsync.valueOrNull ?? const [],);

                  Widget content;
                  switch (_tab) {
                    case 'holidays':
                      content = _entryList(holidays, canManage,
                          empty: 'No holidays this month.',);
                    case 'deadlines':
                      content = _entryList(deadlines, canManage,
                          empty: 'No deadlines this month.',);
                    case 'milestones':
                      content = milestonesAsync.isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),),),)
                          : _milestoneList(milestones);
                    default:
                      content = upcoming.isEmpty
                          ? const Text('Nothing upcoming.')
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              for (final e in upcoming)
                                _entryTile(e, canManage, showDate: true),
                            ],);
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            const ButtonSegment(value: 'upcoming', label: Text('Upcoming')),
                            ButtonSegment(value: 'holidays', label: Text('Holidays (${holidays.length})')),
                            ButtonSegment(value: 'deadlines', label: Text('Deadlines (${deadlines.length})')),
                            ButtonSegment(value: 'milestones', label: Text('Milestones (${milestones.length})')),
                          ],
                          selected: {_tab},
                          onSelectionChanged: (s) => setState(() => _tab = s.first),
                        ),
                      ),
                      const SizedBox(height: 10),
                      content,
                    ],
                  );
                },),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Birthdays/anniversaries falling in the displayed month (web
  /// getMilestonesForMonth: occurrence of dob/joining month-day this year;
  /// anniversaries only after the joining year).
  List<({String name, String type, DateTime date, int? years})> _monthMilestones(
    List<MilestoneProfile> profiles,
  ) {
    final out = <({String name, String type, DateTime date, int? years})>[];
    for (final p in profiles) {
      if (p.dob != null && p.dob!.month == _month.month) {
        out.add((
          name: p.name,
          type: 'birthday',
          date: DateTime(_month.year, p.dob!.month, p.dob!.day),
          years: null,
        ),);
      }
      if (p.joining != null &&
          p.joining!.month == _month.month &&
          p.joining!.year < _month.year) {
        out.add((
          name: p.name,
          type: 'anniversary',
          date: DateTime(_month.year, p.joining!.month, p.joining!.day),
          years: _month.year - p.joining!.year,
        ),);
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  Widget _entryList(List<CalendarEntry> list, bool canManage,
      {required String empty,}) {
    if (list.isEmpty) return Text(empty);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final e in list) _entryTile(e, canManage, showDate: true),
    ],);
  }

  Widget _milestoneList(
    List<({String name, String type, DateTime date, int? years})> list,
  ) {
    final theme = Theme.of(context);
    if (list.isEmpty) return const Text('No milestones this month.');
    return Column(children: [
      for (final m in list)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            m.type == 'birthday' ? Icons.cake_outlined : Icons.celebration_outlined,
            color: m.type == 'birthday'
                ? const Color(0xFFD97706)
                : theme.colorScheme.primary,
          ),
          title: Text(m.name, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            m.type == 'birthday'
                ? 'Birthday'
                : 'Work anniversary${m.years != null ? ' · ${m.years} yr${m.years == 1 ? '' : 's'}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Text('${m.date.day}/${m.date.month}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),),
        ),
    ],);
  }

  Widget _monthHeader() {
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1))),
        Text('${months[_month.month - 1]} ${_month.year}', style: Theme.of(context).textTheme.titleLarge),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1))),
      ],
    );
  }

  Widget _grid(Map<String, List<CalendarEntry>> byDay, Set<int> milestoneDays) {
    final theme = Theme.of(context);
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // Sun=0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = DateTime.now();
    final cells = <Widget>[];
    const wd = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    for (final w in wd) {
      cells.add(Center(child: Text(w, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))));
    }
    for (var i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final entries = byDay[_key(date)] ?? const [];
      final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
      final isSelected = _selected != null && _key(_selected!) == _key(date);
      cells.add(InkWell(
        onTap: () => setState(() => _selected = date),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(8),
            border: isToday ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day', style: TextStyle(fontWeight: isToday ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final t in entries.map((e) => e.type).toSet().take(3))
                    Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: calendarTypeColors(t).$2, shape: BoxShape.circle),
                    ),
                  // Milestone marker (web milestone day modifier).
                  if (milestoneDays.contains(day))
                    Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: const BoxDecoration(
                          color: Color(0xFFD97706), shape: BoxShape.circle,),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),);
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: cells,
    );
  }

  Widget _legend() {
    Widget dot(String type) {
      final (_, fg) = calendarTypeColors(type);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(calendarTypeLabel(type), style: Theme.of(context).textTheme.labelSmall),
      ],);
    }

    return Wrap(spacing: 14, runSpacing: 4, children: [dot('holiday'), dot('deadline'), dot('optional'), dot('event')]);
  }

  Widget _entryTile(CalendarEntry e, bool canManage, {bool showDate = false}) {
    final theme = Theme.of(context);
    final (bg, fg) = calendarTypeColors(e.type);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(calendarTypeIcon(e.type), size: 18, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${showDate ? '${_fmtShort(e.date)} · ' : ''}${calendarTypeLabel(e.type)}${e.isCustom ? ' · custom' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                if (e.description != null && e.description!.isNotEmpty)
                  Text(e.description!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (canManage && e.isCustom && e.id != null)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
              onPressed: () async {
                await ref.read(calendarRepositoryProvider).deleteEvent(e.id!);
                ref.invalidate(calendarEntriesProvider);
              },
            ),
        ],
      ),
    );
  }

  static String _fmtLong(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const wd = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${wd[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _fmtShort(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

void _showAddDialog(BuildContext context, WidgetRef ref, DateTime initial) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _AddEventForm(ref: ref, initial: initial),
    ),
  );
}

class _AddEventForm extends StatefulWidget {
  const _AddEventForm({required this.ref, required this.initial});
  final WidgetRef ref;
  final DateTime initial;
  @override
  State<_AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<_AddEventForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late DateTime _date;
  String _type = 'event';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = widget.initial;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add calendar event', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: DateTime(DateTime.now().year + 2));
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(_fmt(_date))),
          ),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title *')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in kCalendarEventTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setState(() => _type = v ?? 'event'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add event'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await widget.ref.read(calendarRepositoryProvider).addEvent(
            title: _title.text, date: _date, eventType: _type,
            description: _desc.text,
          );
      widget.ref.invalidate(calendarEntriesProvider);
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
}
