import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard_providers.dart';
import 'section_card.dart';

/// Manager/admin team overview (mirrors web TeamReportsWidget): team size,
/// clocked-in today, pending leaves, and task completion. Read-only.
class TeamReportCard extends ConsumerWidget {
  const TeamReportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(teamReportProvider);
    return SectionCard(
      icon: Icons.groups_outlined,
      title: 'Team Overview',
      child: async.when(
        loading: () => const SectionLoading(),
        error: (_, __) => const SectionError('Could not load team overview.'),
        data: (r) {
          if (r == null) return const SizedBox.shrink();
          return Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  _Stat(label: 'Team size', value: '${r.teamSize}'),
                  _Stat(label: 'Clocked in', value: '${r.clockedInToday}'),
                  _Stat(label: 'Pending leave', value: '${r.pendingLeaves}'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Task completion', style: theme.textTheme.bodyMedium),
                  Text('${r.taskCompletionPct}%  (${r.doneTasks}/${r.totalTasks})',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: r.taskCompletionPct / 100,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),),
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),),
        ],
      ),
    );
  }
}
