import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard_providers.dart';
import 'section_card.dart';

/// Employee self-summary (mirrors web PersonalReportsWidget): attendance
/// progress vs monthly target, manager(s), teammates, annual leave balance.
class PersonalReportCard extends ConsumerWidget {
  const PersonalReportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(personalReportProvider);
    return SectionCard(
      icon: Icons.insights_outlined,
      title: 'My Summary',
      child: async.when(
        loading: () => const SectionLoading(),
        error: (_, __) => const SectionError('Could not load summary.'),
        data: (r) {
          if (r == null) return const SectionEmpty('No data.');
          final pct = (r.progress * 100).round();
          final hoursText = _fmtH(r.monthlyHours);
          final targetText = _fmtH(r.targetHours);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Attendance this month',
                      style: theme.textTheme.bodyMedium,),
                  Text('$hoursText / $targetText h',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: r.progress,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Text('$pct% of monthly target',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),),
              const Divider(height: 24),
              if (r.managerNames.isNotEmpty)
                _kv(theme, 'Reports to', r.managerNames.join(', ')),
              if (r.teammateCount > 0)
                _kv(theme, 'Teammates', '${r.teammateCount}'),
              if (r.annual != null)
                _kv(theme, 'Annual leave',
                    '${_fmtD(r.annual!.remaining)} / ${_fmtD(r.annual!.totalDays)} left',),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(k,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),),
            ),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),),
            ),
          ],
        ),
      );

  static String _fmtH(double h) =>
      h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);
  static String _fmtD(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : '$n';
}
