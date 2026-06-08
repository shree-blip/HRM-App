import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/calendar_models.dart';
import '../data/calendar_providers.dart';

/// Dashboard card: next few upcoming company calendar entries + "View calendar".
class CompanyCalendarCard extends ConsumerWidget {
  const CompanyCalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(calendarEntriesProvider);

    return Card(
      child: InkWell(
        onTap: () => context.push('/calendar'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Company Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Holidays, deadlines & events',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              async.when(
                loading: () => const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
                error: (_, __) => Text('Could not load calendar.', style: theme.textTheme.bodySmall),
                data: (entries) {
                  final today = DateTime.now();
                  final upcoming = entries
                      .where((e) => !e.date.isBefore(DateTime(today.year, today.month, today.day)))
                      .take(4)
                      .toList();
                  if (upcoming.isEmpty) {
                    return Text('Nothing upcoming.', style: theme.textTheme.bodySmall);
                  }
                  return Column(children: [for (final e in upcoming) _row(theme, e)]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, CalendarEntry e) {
    final (bg, fg) = calendarTypeColors(e.type);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(calendarTypeIcon(e.type), size: 16, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text('${months[e.date.month - 1]} ${e.date.day}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        ],
      ),
    );
  }
}
