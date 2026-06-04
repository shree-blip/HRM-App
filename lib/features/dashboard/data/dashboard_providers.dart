import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'dashboard_repository.dart';

final dashboardRepositoryProvider =
    Provider<DashboardRepository>((_) => DashboardRepository());

/// Stat-card numbers. Auto-refreshes if the user/role changes.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>(
  (ref) async {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    if (user == null) {
      return const DashboardSummary(
        employeeCount: 0,
        monthlyHours: 0,
        pendingTasks: 0,
        tasksDueToday: 0,
        pendingLeaves: 0,
        onLeaveTodayNames: [],
      );
    }
    return ref.read(dashboardRepositoryProvider).summary(
          userId: user.id,
          isManager: auth.isManager,
        );
  },
);

final announcementsProvider =
    FutureProvider.autoDispose<List<AnnouncementItem>>((ref) async {
  // Keep the dashboard logged-in before fetching.
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.read(dashboardRepositoryProvider).announcements();
});

final leaveBalancesProvider =
    FutureProvider.autoDispose<List<LeaveBalanceItem>>((ref) async {
  final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (userId == null) return const [];
  return ref.read(dashboardRepositoryProvider).leaveBalances(userId);
});
