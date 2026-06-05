import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/attendance_providers.dart';
import 'widgets/attendance_history_list.dart';
import 'widgets/team_attendance_view.dart';
import 'widgets/time_clock_card.dart';

/// Attendance screen: "My" tab (clock + today status + history) and, for
/// managers/admins, a "Team" tab.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(authControllerProvider.select((s) => s.isManager));

    return DefaultTabController(
      length: isManager ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendance'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                ref.invalidate(attendanceStatsProvider);
                ref.invalidate(attendanceHistoryProvider);
                ref.invalidate(teamAttendanceProvider);
              },
            ),
          ],
          bottom: isManager
              ? const TabBar(tabs: [Tab(text: 'My Attendance'), Tab(text: 'Team')])
              : null,
        ),
        drawer: const AppDrawer(currentRoute: '/attendance'),
        body: isManager
            ? const TabBarView(children: [_MyTab(), TeamAttendanceView()])
            : const _MyTab(),
      ),
    );
  }
}

class _MyTab extends ConsumerWidget {
  const _MyTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(attendanceStatsProvider);
        ref.invalidate(attendanceHistoryProvider);
        await ref.read(attendanceHistoryProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TimeClockCard(),
          const SizedBox(height: 20),
          Text('My Attendance History',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),),
          Text('This month',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 8),
          const AttendanceHistoryList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
