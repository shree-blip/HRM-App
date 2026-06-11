import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/auth_state.dart';
import '../core/navigation/nav_items.dart';
import '../core/widgets/app_loader.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/approvals/presentation/approvals_screen.dart';
import '../features/attendance/presentation/attendance_screen.dart';
import '../features/common/coming_soon_screen.dart';
import '../features/announcements/presentation/announcements_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/invoices/presentation/invoices_screen.dart';
import '../features/loans/presentation/loans_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/tasks/presentation/tasks_screen.dart';
import '../features/leave/presentation/leave_screen.dart';
import '../features/logsheet/presentation/logsheet_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/access_control/presentation/access_control_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/my_onboarding_screen.dart';
import '../features/onboarding/presentation/my_offboarding_screen.dart';
import '../features/hiring/presentation/hiring_screen.dart';
import '../features/timezone/presentation/timezone_screen.dart';
import '../features/employees/data/employee.dart';
import '../features/employees/presentation/employee_detail_screen.dart';
import '../features/employees/presentation/employees_screen.dart';

/// Route paths used across the app.
class Routes {
  const Routes._();
  static const splash = '/splash';
  static const auth = '/auth';
  static const forgotPassword = '/forgot-password';
  static const dashboard = '/';
}

const _publicRoutes = {Routes.auth, Routes.forgotPassword};

/// Android back-button guard for authenticated top-level routes. The system
/// back must never reveal the auth screen after login: from any drawer
/// destination back returns to the Dashboard; from the Dashboard it leaves
/// the app. Pushed sub-routes (detail screens, dialogs) still pop normally
/// because they sit above this route in the navigator.
class _RootBackGuard extends StatelessWidget {
  const _RootBackGuard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final loc = GoRouterState.of(context).matchedLocation;
        if (loc == Routes.dashboard) {
          SystemNavigator.pop();
        } else {
          context.go(Routes.dashboard);
        }
      },
      child: child,
    );
  }
}

/// GoRouter wired to the auth state. The router instance is stable; auth
/// changes trigger a redirect via [refreshListenable].
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthStatus>(
    authControllerProvider.select((s) => s.status),
    (_, __) => refresh.value++,
    fireImmediately: false,
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (auth.status == AuthStatus.loading) {
        return loc == Routes.splash ? null : Routes.splash;
      }

      final loggedIn = auth.status == AuthStatus.authenticated;
      if (!loggedIn) {
        return _publicRoutes.contains(loc) ? null : Routes.auth;
      }

      // Authenticated: keep users out of splash/auth screens.
      if (loc == Routes.splash || _publicRoutes.contains(loc)) {
        return Routes.dashboard;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, __) => const AppLoader(),
      ),
      GoRoute(
        path: Routes.auth,
        builder: (_, __) => const AuthScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.dashboard,
        builder: (_, __) => const _RootBackGuard(child: DashboardScreen()),
      ),
      // Employee Management (Phase 3) — list + read-only detail.
      GoRoute(
        path: '/employees',
        builder: (_, __) => const _RootBackGuard(child: EmployeesScreen()),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) => EmployeeDetailScreen(
              employeeId: state.pathParameters['id']!,
              initial: state.extra as EmployeeDirectoryItem?,
            ),
          ),
        ],
      ),
      // Attendance (Phase 4).
      GoRoute(
        path: '/attendance',
        builder: (_, __) => const _RootBackGuard(child: AttendanceScreen()),
      ),
      // Leave (Phase 5).
      GoRoute(
        path: '/leave',
        builder: (_, __) => const _RootBackGuard(child: LeaveScreen()),
      ),
      // Approvals (Phase 6).
      GoRoute(
        path: '/approvals',
        builder: (_, __) => const _RootBackGuard(child: ApprovalsScreen()),
      ),
      // Reports (Phase 7).
      GoRoute(
        path: '/reports',
        builder: (_, __) => const _RootBackGuard(child: ReportsScreen()),
      ),
      // Log Sheet (Phase 8).
      GoRoute(
        path: '/log-sheet',
        builder: (_, __) => const _RootBackGuard(child: LogSheetScreen()),
      ),
      // Documents (Phase 9).
      GoRoute(
        path: '/documents',
        builder: (_, __) => const _RootBackGuard(child: DocumentsScreen()),
      ),
      // Support, Bugs & Grievances (Phase 10).
      GoRoute(
        path: '/support',
        builder: (_, __) => const _RootBackGuard(child: SupportScreen()),
      ),
      // Loans, Invoices, Announcements (Phase 11).
      GoRoute(
        path: '/loans',
        builder: (_, __) => const _RootBackGuard(child: LoansScreen()),
      ),
      GoRoute(
        path: '/invoices',
        builder: (_, __) => const _RootBackGuard(child: InvoicesScreen()),
      ),
      GoRoute(
        path: '/announcements',
        builder: (_, __) => const _RootBackGuard(child: AnnouncementsScreen()),
      ),
      // Calendar + Profile (Phase 12).
      GoRoute(
        path: '/calendar',
        builder: (_, __) => const _RootBackGuard(child: CalendarScreen()),
      ),
      // Notifications (Critical Fix 2).
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const _RootBackGuard(child: NotificationsScreen()),
      ),
      // Tasks (Critical Fix 3).
      GoRoute(
        path: '/tasks',
        builder: (_, __) => const _RootBackGuard(child: TasksScreen()),
      ),
      // Settings.
      GoRoute(
        path: '/settings',
        builder: (_, __) => const _RootBackGuard(child: SettingsScreen()),
      ),
      // Access Control.
      GoRoute(
        path: '/access-control',
        builder: (_, __) => const _RootBackGuard(child: AccessControlScreen()),
      ),
      // Onboarding / Offboarding.
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const _RootBackGuard(child: OnboardingScreen()),
      ),
      GoRoute(
        path: '/my-onboarding',
        builder: (_, __) => const _RootBackGuard(child: MyOnboardingScreen()),
      ),
      GoRoute(
        path: '/my-offboarding',
        builder: (_, __) => const _RootBackGuard(child: MyOffboardingScreen()),
      ),
      // Hiring.
      GoRoute(
        path: '/hiring',
        builder: (_, __) => const _RootBackGuard(child: HiringScreen()),
      ),
      // Timezone Management.
      GoRoute(
        path: '/timezone-management',
        builder: (_, __) => const _RootBackGuard(child: TimezoneScreen()),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const _RootBackGuard(child: ProfileScreen()),
      ),
      // Placeholder routes for modules that ship in later phases. Keeps the
      // drawer + dashboard links functional without dead-ends.
      for (final entry in kPlaceholderRoutes.entries)
        GoRoute(
          path: entry.key,
          builder: (_, __) => ComingSoonScreen(
            title: entry.value.title,
            route: entry.key,
            phase: entry.value.phase,
          ),
        ),
    ],
  );
});
