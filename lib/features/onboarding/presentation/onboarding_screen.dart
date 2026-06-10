import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../employees/data/employee.dart';
import '../../employees/data/employees_providers.dart';
import '../data/onboarding_models.dart';
import '../data/onboarding_providers.dart';
import 'new_hire_form.dart';
import 'onboarding_widgets.dart';

/// Admin Onboarding/Offboarding (parity with the web Onboarding page).
/// Gated by manage_onboarding.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsControllerProvider);
    final canManage = perms.has(Permission.manageOnboarding);
    final stillResolving = perms.loading && !canManage;

    if (stillResolving) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('Onboarding')),
        drawer: const AppDrawer(currentRoute: '/onboarding'),
        body: const OnbEmptyState(icon: Icons.lock_outline, title: 'Access Denied', message: "You don't have permission to access this page."),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Onboarding'),
          bottom: const TabBar(tabs: [Tab(text: 'Onboarding'), Tab(text: 'Offboarding')]),
        ),
        drawer: const AppDrawer(currentRoute: '/onboarding'),
        body: const TabBarView(children: [_OnboardingTab(), _OffboardingTab()]),
      ),
    );
  }
}

// ════════════════ Onboarding tab ════════════════
class _OnboardingTab extends ConsumerWidget {
  const _OnboardingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    if (state.loading) return const Center(child: CircularProgressIndicator());

    final active = state.active;
    final now = DateTime.now();
    final startingSoon = active.where((w) {
      final d = DateTime.tryParse(w.startDate);
      if (d == null) return false;
      final days = d.difference(now).inDays;
      return d.isAfter(now) && days <= 7;
    }).length;
    final completedThisMonth = state.completed.where((w) {
      final d = w.completedAt != null ? DateTime.tryParse(w.completedAt!) : null;
      return d != null && d.year == now.year && d.month == now.month;
    }).length;

    return RefreshIndicator(
      onRefresh: () => ref.read(onboardingControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              _stat(context, 'Active Onboarding', active.length.toString(), Icons.person_add_alt, Colors.orange.shade700),
              _stat(context, 'Starting Soon', startingSoon.toString(), Icons.event_outlined, Colors.blue.shade700),
              _stat(context, 'Completed This Month', completedThisMonth.toString(), Icons.check_circle_outline, Colors.green.shade700),
              _stat(context, 'Total Completed', state.completed.length.toString(), Icons.verified_outlined, theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Add New Hire'),
              onPressed: () => showNewHireForm(context, ref),
            ),
          ),
          const SizedBox(height: 12),
          Text('Active Onboarding (${active.length})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (active.isEmpty)
            const OnbEmptyState(icon: Icons.person_add_alt_1_outlined, title: 'No active onboarding workflows', message: 'Add a new hire to get started.')
          else
            for (final w in active) _OnboardingCard(workflow: w),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              height: 36, width: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingCard extends ConsumerWidget {
  const _OnboardingCard({required this.workflow});
  final OnboardingWorkflow workflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final e = workflow.employee;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(e?.initials ?? '??', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e?.fullName ?? 'Employee', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${e?.jobTitle ?? 'Employee'} • ${e?.department ?? 'General'}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (e?.email != null) Text(e!.email!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text('Start: ${onbDate(workflow.startDate)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                onbStatusBadge(context, workflow.status),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],),
            ],),
            const SizedBox(height: 6),
            Row(children: [
              Text('Progress', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text('${workflow.progress}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: workflow.progress / 100, minHeight: 6)),
            const SizedBox(height: 10),
            for (final t in workflow.tasks) _taskRow(context, ref, t),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, WidgetRef ref, OnboardingTask t) {
    final theme = Theme.of(context);
    final green = Colors.green.shade700;
    return InkWell(
      onTap: () => ref.read(onboardingControllerProvider.notifier).toggleTask(t.id, t.isCompleted),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.isCompleted ? green.withValues(alpha: 0.1) : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(t.isCompleted ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: t.isCompleted ? green : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: TextStyle(fontSize: 13, decoration: t.isCompleted ? TextDecoration.lineThrough : null, color: t.isCompleted ? green : null)),
              if (t.description != null && t.description!.isNotEmpty)
                Text(t.description!, style: theme.textTheme.bodySmall?.copyWith(color: t.isCompleted ? green.withValues(alpha: 0.7) : theme.colorScheme.onSurfaceVariant)),
            ],),
          ),
        ],),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Onboarding Workflow?'),
        content: const Text('This permanently deletes this onboarding workflow and all its tasks. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(onboardingControllerProvider.notifier).deleteOnboarding(workflow.id);
  }
}

// ════════════════ Offboarding tab ════════════════
class _OffboardingTab extends ConsumerWidget {
  const _OffboardingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(onboardingControllerProvider);
    if (state.loading) return const Center(child: CircularProgressIndicator());
    final active = state.activeOffboarding;
    final employees = ref.watch(employeesListProvider).valueOrNull ?? const [];

    return RefreshIndicator(
      onRefresh: () => ref.read(onboardingControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: const Text('Start Offboarding'),
              onPressed: () => _startOffboarding(context, ref, employees),
            ),
          ),
          const SizedBox(height: 12),
          Text('Active Offboarding (${active.length})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (active.isEmpty)
            const OnbEmptyState(icon: Icons.logout_outlined, title: 'No active offboarding workflows', message: 'Start an offboarding when an employee is leaving.')
          else
            for (final w in active) _OffboardingCard(workflow: w, employees: employees),
        ],
      ),
    );
  }

  Future<void> _startOffboarding(BuildContext context, WidgetRef ref, List<EmployeeDirectoryItem> employees) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _StartOffboardingForm(employees: employees.where((e) => e.displayStatus == 'active' || e.displayStatus == 'probation').toList()),
      ),
    );
  }
}

class _OffboardingCard extends ConsumerWidget {
  const _OffboardingCard({required this.workflow, required this.employees});
  final OffboardingWorkflow workflow;
  final List<EmployeeDirectoryItem> employees;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final emp = employees.where((e) => e.id == workflow.employeeId).cast<EmployeeDirectoryItem?>().firstWhere((e) => true, orElse: () => null);
    final lastDay = DateTime.tryParse(workflow.lastWorkingDate);
    final daysLeft = lastDay?.difference(DateTime.now()).inDays;
    final done = {
      'exit_interview_completed': workflow.exitInterview,
      'assets_recovered': workflow.assetsRecovered,
      'access_revoked': workflow.accessRevoked,
      'final_settlement_processed': workflow.finalSettlement,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.error.withValues(alpha: 0.1),
                child: Text(emp?.initials ?? '??', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.error)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(emp?.fullName ?? 'Employee', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(emp?.jobTitle ?? 'Employee', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('Last Day: ${onbDate(workflow.lastWorkingDate)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (daysLeft != null && daysLeft > 0) ...[
                      const SizedBox(width: 8),
                      Text('$daysLeft days left', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ] else if (daysLeft != null && daysLeft <= 0 && daysLeft > -7) ...[
                      const SizedBox(width: 8),
                      Text('Past last day', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                    ],
                  ],),
                  if (workflow.reason != null && workflow.reason!.isNotEmpty)
                    Text('Reason: ${workflow.reason}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                onbStatusBadge(context, workflow.status),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],),
            ],),
            const SizedBox(height: 6),
            Row(children: [
              Text('Progress', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text('${workflow.progress}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: workflow.progress / 100, minHeight: 6)),
            const SizedBox(height: 10),
            for (final s in kOffboardingStepDefs) _stepRow(context, ref, s.key, s.label, s.description, done[s.key] ?? false),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(BuildContext context, WidgetRef ref, String key, String label, String desc, bool completed) {
    final theme = Theme.of(context);
    final green = Colors.green.shade700;
    return InkWell(
      onTap: completed ? null : () => ref.read(onboardingControllerProvider.notifier).updateOffboarding(workflow.id, key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: completed ? green.withValues(alpha: 0.1) : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(completed ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: completed ? green : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 13, decoration: completed ? TextDecoration.lineThrough : null, color: completed ? green : null)),
              Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: completed ? green.withValues(alpha: 0.7) : theme.colorScheme.onSurfaceVariant)),
            ],),
          ),
        ],),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Offboarding Workflow?'),
        content: const Text('This permanently deletes this offboarding workflow. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(onboardingControllerProvider.notifier).deleteOffboarding(workflow.id);
  }
}

class _StartOffboardingForm extends ConsumerStatefulWidget {
  const _StartOffboardingForm({required this.employees});
  final List<EmployeeDirectoryItem> employees;
  @override
  ConsumerState<_StartOffboardingForm> createState() => _StartOffboardingFormState();
}

class _StartOffboardingFormState extends ConsumerState<_StartOffboardingForm> {
  String? _employeeId;
  DateTime? _lastDay;
  String? _reason;
  bool _busy = false;
  String? _error;

  static const _reasons = ['resignation', 'termination', 'retirement', 'contract_end', 'relocation', 'other'];

  Future<void> _submit() async {
    if (_employeeId == null || _lastDay == null) {
      setState(() => _error = 'Please select an employee and last working date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await ref.read(onboardingControllerProvider.notifier).createOffboarding(
            _employeeId!,
            '${_lastDay!.year}-${_lastDay!.month.toString().padLeft(2, '0')}-${_lastDay!.day.toString().padLeft(2, '0')}',
            _reason,
          );
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start Offboarding', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Initiate the offboarding process for a departing employee.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _employeeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Employee *'),
            items: [for (final e in widget.employees) DropdownMenuItem(value: e.id, child: Text('${e.fullName} - ${e.jobTitle ?? ''}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _employeeId = v),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _lastDay ?? DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 2));
              if (d != null) setState(() => _lastDay = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Last Working Date *'),
              child: Text(_lastDay == null ? 'Select date' : '${_lastDay!.year}-${_lastDay!.month.toString().padLeft(2, '0')}-${_lastDay!.day.toString().padLeft(2, '0')}'),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason for Leaving'),
            items: [for (final r in _reasons) DropdownMenuItem(value: r, child: Text(r[0].toUpperCase() + r.substring(1).replaceAll('_', ' ')))],
            onChanged: (v) => setState(() => _reason = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Start Offboarding'),
            ),
          ),
        ],
      ),
    );
  }
}
