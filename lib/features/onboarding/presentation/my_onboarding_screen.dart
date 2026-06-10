import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/onboarding_models.dart';
import '../data/onboarding_providers.dart';
import 'onboarding_widgets.dart';

/// Employee self-view of their own onboarding progress (read-only) — mirrors
/// the web MyOnboarding page.
class MyOnboardingScreen extends ConsumerWidget {
  const MyOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(myOnboardingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Onboarding')),
      drawer: const AppDrawer(currentRoute: '/my-onboarding'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load.\n$e', textAlign: TextAlign.center)),
        data: (wf) => wf == null
            ? const OnbEmptyState(
                icon: Icons.person_add_alt_1_outlined,
                title: 'No Onboarding Found',
                message: "Your onboarding information will appear here once it's been set up by your manager.",
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(myOnboardingProvider),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Track your onboarding progress and see what comes next.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                    const SizedBox(height: 12),
                    _progressCard(context, wf),
                    const SizedBox(height: 16),
                    Row(children: [
                      Icon(Icons.checklist_outlined, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text('Onboarding Tasks', style: theme.textTheme.titleSmall),
                    ],),
                    const SizedBox(height: 8),
                    for (final t in wf.tasks) _taskTile(context, t),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _progressCard(BuildContext context, OnboardingWorkflow wf) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Onboarding Progress', style: theme.textTheme.titleMedium),
                        const SizedBox(width: 8),
                        onbStatusBadge(context, wf.status),
                      ],),
                      const SizedBox(height: 4),
                      Text(
                        'Started ${onbDate(wf.startDate)}${wf.targetCompletionDate != null ? ' · Target: ${onbDate(wf.targetCompletionDate!)}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${wf.progress}%', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                  Text('${wf.completedCount} of ${wf.tasks.length} tasks', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: wf.progress / 100, minHeight: 8)),
          ],
        ),
      ),
    );
  }

  Widget _taskTile(BuildContext context, OnboardingTask t) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(t.isCompleted ? Icons.check_circle : Icons.circle_outlined,
            color: t.isCompleted ? Colors.green.shade600 : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), size: 20,),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title,
                style: TextStyle(fontWeight: FontWeight.w500, decoration: t.isCompleted ? TextDecoration.lineThrough : null, color: t.isCompleted ? theme.colorScheme.onSurfaceVariant : null),),
            if (t.description != null && t.description!.isNotEmpty)
              Text(t.description!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (t.isCompleted && t.completedAt != null)
              Text('Completed ${onbDate(t.completedAt!)}', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade600)),
          ],),
        ),
        const SizedBox(width: 8),
        Container(
          height: 32, width: 32,
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Icon(onboardingTaskIcon(t.taskType), size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],),
    );
  }
}
