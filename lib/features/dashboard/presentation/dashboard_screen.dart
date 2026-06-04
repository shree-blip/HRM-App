import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/dashboard_providers.dart';
import '../data/dashboard_repository.dart';
import 'widgets/announcements_card.dart';
import 'widgets/leave_balances_card.dart';
import 'widgets/stat_card.dart';

/// Phase 2 dashboard. Mobile-first: greeting, 2x2 stat grid (real RLS-scoped
/// data), announcements and leave balances. Stat cards deep-link into the
/// relevant module (placeholder until that module ships).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final isManager = auth.isManager;
    final firstName = auth.profile?.firstName.isNotEmpty == true
        ? auth.profile!.firstName
        : 'there';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(dashboardSummaryProvider);
              ref.invalidate(announcementsProvider);
              ref.invalidate(leaveBalancesProvider);
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/'),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(announcementsProvider);
          ref.invalidate(leaveBalancesProvider);
          await ref.read(dashboardSummaryProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Greeting(
              firstName: firstName,
              isManager: isManager,
              roleLabel: _roleLabel(auth.role?.name),
            ),
            const SizedBox(height: 16),
            summaryAsync.when(
              loading: () => const _StatGridSkeleton(),
              error: (e, _) => _ErrorTile(
                message: 'Could not load dashboard stats.',
                onRetry: () => ref.invalidate(dashboardSummaryProvider),
              ),
              data: (s) => _StatGrid(
                summary: s,
                isManager: isManager,
                profileName: auth.profile?.fullName ?? 'Profile',
                department: auth.profile?.department,
              ),
            ),
            const SizedBox(height: 16),
            const AnnouncementsCard(),
            const SizedBox(height: 16),
            const LeaveBalancesCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String? role) => switch (role) {
        'vp' => 'Executive',
        'admin' => 'Admin',
        'supervisor' => 'Supervisor',
        'lineManager' => 'Line Manager',
        _ => '',
      };
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.firstName,
    required this.isManager,
    required this.roleLabel,
  });

  final String firstName;
  final bool isManager;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              'Welcome back, $firstName',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (roleLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  roleLabel,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isManager
              ? "Here's what's happening with your team today."
              : "Here's your personal dashboard overview.",
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.summary,
    required this.isManager,
    required this.profileName,
    required this.department,
  });

  final DashboardSummary summary;
  final bool isManager;
  final String profileName;
  final String? department;

  @override
  Widget build(BuildContext context) {
    final hours = summary.monthlyHours;
    final hoursText = hours == hours.roundToDouble()
        ? '${hours.toInt()}h'
        : '${hours.toStringAsFixed(1)}h';

    final leaveSub = summary.onLeaveTodayNames.isNotEmpty
        ? 'On leave: ${summary.onLeaveTodayNames.take(2).join(', ')}'
            '${summary.onLeaveTodayNames.length > 2 ? ' +${summary.onLeaveTodayNames.length - 2}' : ''}'
        : (summary.pendingLeaves > 0
            ? '${summary.pendingLeaves} pending'
            : 'No one on leave today');

    final cards = <Widget>[
      if (isManager)
        StatCard(
          title: 'Total Employees',
          value: '${summary.employeeCount}',
          subtitle: 'View directory',
          icon: Icons.people_outline,
          iconColor: AppColors.primary,
          onTap: () => context.go('/employees'),
        )
      else
        StatCard(
          title: 'My Profile',
          value: profileName,
          subtitle: department?.isNotEmpty == true ? department! : 'View profile',
          icon: Icons.person_outline,
          iconColor: AppColors.primary,
          onTap: () => context.go('/profile'),
        ),
      StatCard(
        title: 'Hours This Month',
        value: hoursText,
        subtitle: 'View attendance',
        icon: Icons.access_time,
        iconColor: AppColors.success,
        onTap: () => context.go('/attendance'),
      ),
      StatCard(
        title: isManager ? 'Team Tasks' : 'My Tasks',
        value: '${summary.pendingTasks}',
        subtitle: '${summary.tasksDueToday} due today',
        icon: Icons.check_box_outlined,
        iconColor: const Color(0xFFD97706),
        onTap: () => context.go('/tasks'),
      ),
      StatCard(
        title: isManager ? 'Leave Requests' : 'My Leave',
        value: '${summary.pendingLeaves}',
        subtitle: leaveSub,
        icon: Icons.event_available_outlined,
        iconColor: const Color(0xFF2563EB),
        onTap: () => context.go(isManager ? '/approvals' : '/leave'),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.98,
      children: cards,
    );
  }
}

class _StatGridSkeleton extends StatelessWidget {
  const _StatGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.98,
      children: List.generate(
        4,
        (_) => const Card(
          child: Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
