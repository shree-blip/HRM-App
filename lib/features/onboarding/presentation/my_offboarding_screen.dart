import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/onboarding_models.dart';
import '../data/onboarding_providers.dart';
import 'onboarding_widgets.dart';

/// Employee self-view of their own offboarding progress (read-only) — mirrors
/// the web MyOffboarding page.
class MyOffboardingScreen extends ConsumerWidget {
  const MyOffboardingScreen({super.key});

  // Self-view step descriptions differ slightly from the admin labels (web).
  static const _stepText = <String, ({String label, String desc})>{
    'exit_interview_completed': (label: 'Exit Interview', desc: 'Complete your exit interview with HR or your manager.'),
    'assets_recovered': (label: 'Return Company Assets', desc: 'Return all company equipment, keys, and access cards.'),
    'access_revoked': (label: 'Access Revocation', desc: 'System and building access will be revoked by IT.'),
    'final_settlement_processed': (label: 'Final Settlement', desc: 'Final pay, leave encashment, and pending reimbursements.'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(myOffboardingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Offboarding')),
      drawer: const AppDrawer(currentRoute: '/my-offboarding'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load.\n$e', textAlign: TextAlign.center)),
        data: (wf) => wf == null
            ? const OnbEmptyState(
                icon: Icons.person_remove_outlined,
                title: 'No Offboarding Found',
                message: 'No offboarding process has been initiated for your account.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(myOffboardingProvider),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Track your offboarding progress and remaining steps.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                    const SizedBox(height: 12),
                    _progressCard(context, wf),
                    const SizedBox(height: 16),
                    Row(children: [
                      Icon(Icons.checklist_outlined, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text('Offboarding Steps', style: theme.textTheme.titleSmall),
                    ],),
                    const SizedBox(height: 8),
                    for (final s in kOffboardingStepDefs) _stepTile(context, wf, s.key, s.icon),
                  ],
                ),
              ),
      ),
    );
  }

  bool _done(OffboardingWorkflow wf, String key) => switch (key) {
        'exit_interview_completed' => wf.exitInterview,
        'assets_recovered' => wf.assetsRecovered,
        'access_revoked' => wf.accessRevoked,
        _ => wf.finalSettlement,
      };

  Widget _progressCard(BuildContext context, OffboardingWorkflow wf) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Offboarding Progress', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    onbStatusBadge(context, wf.status),
                  ],),
                  const SizedBox(height: 4),
                  if (wf.resignationDate != null)
                    Text('Resigned: ${onbDate(wf.resignationDate!)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text('Last Day: ${onbDate(wf.lastWorkingDate)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (wf.reason != null && wf.reason!.isNotEmpty)
                    Text('Reason: ${wf.reason}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                ],),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${wf.progress}%', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                Text('${[wf.exitInterview, wf.assetsRecovered, wf.accessRevoked, wf.finalSettlement].where((b) => b).length} of 4 steps',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              ],),
            ],),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: wf.progress / 100, minHeight: 8)),
          ],
        ),
      ),
    );
  }

  Widget _stepTile(BuildContext context, OffboardingWorkflow wf, String key, IconData icon) {
    final theme = Theme.of(context);
    final done = _done(wf, key);
    final text = _stepText[key]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(done ? Icons.check_circle : Icons.circle_outlined,
            color: done ? Colors.green.shade600 : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), size: 20,),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text.label, style: TextStyle(fontWeight: FontWeight.w500, decoration: done ? TextDecoration.lineThrough : null, color: done ? theme.colorScheme.onSurfaceVariant : null)),
            Text(text.desc, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (done) Text('Completed', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade600)),
          ],),
        ),
        const SizedBox(width: 8),
        Container(
          height: 32, width: 32,
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],),
    );
  }
}
