import 'package:flutter/material.dart';
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
import '../features/documents/presentation/documents_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/leave/presentation/leave_screen.dart';
import '../features/logsheet/presentation/logsheet_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
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
        builder: (_, __) => const DashboardScreen(),
      ),
      // Employee Management (Phase 3) — list + read-only detail.
      GoRoute(
        path: '/employees',
        builder: (_, __) => const EmployeesScreen(),
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
        builder: (_, __) => const AttendanceScreen(),
      ),
      // Leave (Phase 5).
      GoRoute(
        path: '/leave',
        builder: (_, __) => const LeaveScreen(),
      ),
      // Approvals (Phase 6).
      GoRoute(
        path: '/approvals',
        builder: (_, __) => const ApprovalsScreen(),
      ),
      // Reports (Phase 7).
      GoRoute(
        path: '/reports',
        builder: (_, __) => const ReportsScreen(),
      ),
      // Log Sheet (Phase 8).
      GoRoute(
        path: '/log-sheet',
        builder: (_, __) => const LogSheetScreen(),
      ),
      // Documents (Phase 9).
      GoRoute(
        path: '/documents',
        builder: (_, __) => const DocumentsScreen(),
      ),
      // Support, Bugs & Grievances (Phase 10).
      GoRoute(
        path: '/support',
        builder: (_, __) => const SupportScreen(),
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
