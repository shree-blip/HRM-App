import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard_providers.dart';
import 'section_card.dart';

/// Birthdays/anniversaries, upcoming deadlines, and holidays (mirrors the web
/// DailyTimelineWidget). Read-only.
class DailyTimelineCard extends ConsumerWidget {
  const DailyTimelineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailyTimelineProvider);
    return SectionCard(
      icon: Icons.event_note_outlined,
      title: 'Daily Timeline',
      child: async.when(
        loading: () => const SectionLoading(),
        error: (_, __) => const SectionError('Could not load timeline.'),
        data: (data) {
          final empty = data.milestones.isEmpty &&
              data.deadlines.isEmpty &&
              data.holidays.isEmpty;
          if (empty) return const SectionEmpty('Nothing upcoming.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.milestones.isNotEmpty) ...[
                const _GroupLabel('Milestones'),
                for (final m in data.milestones)
                  _Row(
                    icon: m.type == 'birthday'
                        ? Icons.cake_outlined
                        : Icons.workspace_premium_outlined,
                    title: m.type == 'birthday'
                        ? '${m.name} · Birthday'
                        : '${m.name} · ${m.years ?? ''} yr anniversary',
                    when: _daysLabel(m.daysUntil),
                  ),
              ],
              if (data.deadlines.isNotEmpty) ...[
                const _GroupLabel('Upcoming Deadlines'),
                for (final d in data.deadlines)
                  _Row(
                    icon: Icons.flag_outlined,
                    title: d.title,
                    when: d.eventDate,
                  ),
              ],
              if (data.holidays.isNotEmpty) ...[
                const _GroupLabel('Holidays & Observances'),
                for (final h in data.holidays)
                  _Row(
                    icon: Icons.celebration_outlined,
                    title: h.name,
                    when: _daysLabel(h.daysUntil),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _daysLabel(int days) => switch (days) {
        0 => 'Today',
        1 => 'Tomorrow',
        _ => 'in $days days',
      };
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.when});
  final IconData icon;
  final String title;
  final String when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            when,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
