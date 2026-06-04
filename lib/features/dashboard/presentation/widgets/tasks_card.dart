import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/dashboard_providers.dart';
import '../../data/dashboard_repository.dart';
import 'section_card.dart';

/// Recent tasks list (mirrors the web TasksWidget — read-only, taps to Tasks).
class TasksCard extends ConsumerWidget {
  const TasksCard({super.key, required this.isManager});
  final bool isManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentTasksProvider);
    return SectionCard(
      icon: Icons.check_box_outlined,
      title: isManager ? 'Team Tasks' : 'My Tasks',
      onViewAll: () => context.go('/tasks'),
      child: async.when(
        loading: () => const SectionLoading(),
        error: (_, __) => const SectionError('Could not load tasks.'),
        data: (tasks) {
          if (tasks.isEmpty) return const SectionEmpty('No tasks yet.');
          return Column(
            children: [for (final t in tasks) _TaskRow(task: t)],
          );
        },
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _PriorityDot(priority: task.priority),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (task.clientName?.isNotEmpty == true)
                  Text(
                    task.clientName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (task.dueDate != null)
            Text(
              task.dueDate!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});
  final String? priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'high' || 'urgent' => const Color(0xFFDC2626),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF2563EB),
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
