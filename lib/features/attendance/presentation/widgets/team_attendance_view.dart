import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/attendance_providers.dart';

/// Manager/admin team attendance for the current month (RLS-scoped): each
/// member's total net hours and days worked, sorted by hours.
class TeamAttendanceView extends ConsumerWidget {
  const TeamAttendanceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(teamAttendanceProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load team attendance.')),
      data: (members) {
        if (members.isEmpty) {
          return const Center(child: Text('No team attendance this month.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final m = members[i];
            final h = m.totalHours;
            final hours =
                h == h.roundToDouble() ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    _initials(m.name),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(m.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,),
                subtitle: Text('${m.daysWorked} day${m.daysWorked == 1 ? '' : 's'} worked'),
                trailing: Text(hours,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),),
              ),
            );
          },
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final f = parts.first[0];
    final l = parts.length > 1 ? parts.last[0] : '';
    return '$f$l'.toUpperCase();
  }
}
