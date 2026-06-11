import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/team/team_scope.dart';
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
    // Non-VP managers see team-scoped pending leave (web useLeaveRequests);
    // employees and VP/Admin keep the RLS scope.
    final scope = await ref.watch(teamScopeProvider.future);
    final leaveScope =
        (auth.isManager && !scope.orgWide) ? scope.userIds : null;
    return ref.read(dashboardRepositoryProvider).summary(
          userId: user.id,
          isManager: auth.isManager,
          leaveScopeUserIds: leaveScope,
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

final recentTasksProvider =
    FutureProvider.autoDispose<List<TaskItem>>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.read(dashboardRepositoryProvider).recentTasks();
});

final recentLeaveProvider =
    FutureProvider.autoDispose<List<LeaveItem>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null) return const [];
  // Non-VP managers see their team's requests only (+ their own), matching
  // the web LeaveWidget; employees/VP keep the RLS scope.
  final scope = await ref.watch(teamScopeProvider.future);
  final leaveScope = (auth.isManager && !scope.orgWide)
      ? [...scope.userIds, auth.user!.id]
      : null;
  return ref
      .read(dashboardRepositoryProvider)
      .recentLeave(scopeUserIds: leaveScope);
});

/// Daily timeline: milestones + deadlines + holidays in one bundle.
typedef TimelineData = ({
  List<MilestoneItem> milestones,
  List<CalendarItem> deadlines,
  List<HolidayItem> holidays,
});

final dailyTimelineProvider =
    FutureProvider.autoDispose<TimelineData>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  final repo = ref.read(dashboardRepositoryProvider);
  final results = await Future.wait([
    repo.milestones(),
    repo.upcomingDeadlines(),
    repo.upcomingHolidays(),
  ]);
  return (
    milestones: results[0] as List<MilestoneItem>,
    deadlines: results[1] as List<CalendarItem>,
    holidays: results[2] as List<HolidayItem>,
  );
});

final personalReportProvider =
    FutureProvider.autoDispose<PersonalReport?>((ref) async {
  final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (userId == null) return null;
  return ref.read(dashboardRepositoryProvider).personalReport(userId);
});

final teamReportProvider =
    FutureProvider.autoDispose<TeamReport?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isManager) return null;
  return ref.read(dashboardRepositoryProvider).teamReport();
});
