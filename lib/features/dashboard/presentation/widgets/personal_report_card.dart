import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard_providers.dart';
import '../../data/dashboard_repository.dart';
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
              // Reports To — full list with roles (web PersonalReportsWidget).
              Text('REPORTS TO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),),
              const SizedBox(height: 6),
              if (r.managers.isEmpty)
                Text('Not assigned to a manager yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),)
              else
                for (final p in r.managers) _person(theme, p, isManager: true),
              const SizedBox(height: 12),
              // Teammates — everyone under the same manager(s).
              Text('TEAMMATES (${r.teammates.length})',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),),
              const SizedBox(height: 6),
              if (r.teammates.isEmpty)
                Text('No teammates yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),)
              else
                for (final p in r.teammates) _person(theme, p),
              if (r.annual != null) ...[
                const Divider(height: 24),
                _kv(theme, 'Annual leave',
                    '${_fmtD(r.annual!.remaining)} / ${_fmtD(r.annual!.totalDays)} left',),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _person(ThemeData theme, PersonRef p, {bool isManager = false}) {
    final initials = p.name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(initials,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(p.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13,),),
                    ),
                    if (isManager) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.workspace_premium,
                          size: 12, color: theme.colorScheme.primary,),
                    ],
                  ],
                ),
                if (p.jobTitle != null && p.jobTitle!.isNotEmpty)
                  Text(p.jobTitle!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),),
              ],
            ),
          ),
        ],
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
