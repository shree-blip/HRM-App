import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/leave_calc.dart';
import '../../data/leave_models.dart';
import '../../data/leave_providers.dart';

/// Leave balance summary: Annual (progress), Special (types taken), Leave in
/// Lieu (days used) — mirrors the web balance cards.
class LeaveBalanceCards extends ConsumerWidget {
  const LeaveBalanceCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(leaveBalancesProvider);
    final requestsAsync = ref.watch(myLeaveRequestsProvider);

    return balancesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (balances) {
        final requests = requestsAsync.valueOrNull ?? const [];
        final approved =
            requests.where((r) => r.status == 'approved').toList();

        // Annual bucket (Annual + Other Leave - Sick Leave).
        LeaveBalance? annual;
        for (final b in balances) {
          if (b.leaveType == 'Annual Leave') annual = b;
        }
        final annualTotal = annual?.totalDays ?? kDefaultAnnualDays;
        final annualUsed = annual?.usedDays ?? 0;

        // Special types taken.
        final specialTaken = <String>{
          for (final r in approved)
            if (isSpecialLeave(r.leaveType)) r.leaveType,
        };

        // Leave in lieu days.
        final lieuUsed = approved
            .where((r) => isLeaveInLieu(r.leaveType))
            .fold<num>(0, (s, r) => s + r.days);

        return Column(
          children: [
            _AnnualCard(total: annualTotal, used: annualUsed),
            const SizedBox(height: 10),
            _SpecialCard(taken: specialTaken),
            const SizedBox(height: 10),
            _LieuCard(used: lieuUsed),
          ],
        );
      },
    );
  }
}

class _AnnualCard extends StatelessWidget {
  const _AnnualCard({required this.total, required this.used});
  final num total;
  final num used;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = total - used;
    final pct = total <= 0 ? 0.0 : (used / total).clamp(0, 1).toDouble();
    final over = used > total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available_outlined,
                    color: theme.colorScheme.primary,),
                const SizedBox(width: 8),
                Text('Annual Leave',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),),
                const Spacer(),
                Text('${_n(remaining)} left',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: over ? theme.colorScheme.error : null,),),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                color: over ? theme.colorScheme.error : null,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text('${_n(used)} used of ${_n(total)} days'
                '${over ? '  ·  +${_n(used - total)} over' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          ],
        ),
      ),
    );
  }
}

class _SpecialCard extends StatelessWidget {
  const _SpecialCard({required this.taken});
  final Set<String> taken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    color: theme.colorScheme.primary,),
                const SizedBox(width: 8),
                Text('Special Leave',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),),
                const Spacer(),
                Text('Category based', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in kSpecialLeaveTypes.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      taken.contains(entry.key)
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 16,
                      color: taken.contains(entry.key)
                          ? const Color(0xFF16A34A)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(entry.key)),
                    Text('${entry.value} days',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,),),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LieuCard extends StatelessWidget {
  const _LieuCard({required this.used});
  final num used;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leave in Lieu',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),),
                  Text('Work a holiday → take a day off',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,),),
                ],
              ),
            ),
            Text('${_n(used)} used',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),),
          ],
        ),
      ),
    );
  }
}

String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
