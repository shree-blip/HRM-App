import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/attendance_providers.dart';

/// Dashboard card (managers/admins): live "today" team clock status counts.
/// Tapping opens the Attendance screen's team tab.
class RealtimeAttendanceCard extends ConsumerWidget {
  const RealtimeAttendanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(liveAttendanceSummaryProvider);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/attendance'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Real-Time Attendance',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => ref.invalidate(liveAttendanceSummaryProvider),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Could not load live attendance.'),
                ),
                data: (s) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Count(label: 'Working', value: s.working, color: const Color(0xFF16A34A)),
                    _Count(label: 'Break', value: s.onBreak, color: const Color(0xFFD97706)),
                    _Count(label: 'Paused', value: s.paused, color: const Color(0xFF4F46E5)),
                    _Count(label: 'Out', value: s.out, color: const Color(0xFF6B7280)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('$value',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: color),),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
      ],
    );
  }
}
