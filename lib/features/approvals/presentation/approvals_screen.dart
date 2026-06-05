import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../attendance/data/attendance_providers.dart';
import '../../leave/data/leave_providers.dart';
import '../../leave/presentation/widgets/leave_approvals_view.dart';
import '../../support/data/asset_providers.dart';
import 'asset_approvals_view.dart';
import 'attendance_approvals_view.dart';

/// Unified Approvals page (Phase 6): Leave, Attendance adjustments, and Asset
/// requests, with a pending summary. Tabs are permission/role gated.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsControllerProvider);
    final isManager = ref.watch(authControllerProvider.select((s) => s.isManager));
    final canApproveLeave = perms.has(Permission.approveLeave);

    final tabs = <({String label, Widget view})>[
      if (canApproveLeave) (label: 'Leave', view: const LeaveApprovalsView()),
      if (isManager) (label: 'Attendance', view: const AttendanceApprovalsView()),
      if (isManager) (label: 'Assets', view: const AssetApprovalsView()),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Approvals')),
        drawer: const AppDrawer(currentRoute: '/approvals'),
        body: const Center(child: Text('You have no approvals access.')),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Approvals'),
          bottom: tabs.length > 1
              ? TabBar(tabs: [for (final t in tabs) Tab(text: t.label)])
              : null,
        ),
        drawer: const AppDrawer(currentRoute: '/approvals'),
        body: Column(
          children: [
            const _PendingSummary(),
            Expanded(
              child: tabs.length > 1
                  ? TabBarView(children: [for (final t in tabs) t.view])
                  : tabs.first.view,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pending counts across Leave / Attendance / Assets.
class _PendingSummary extends ConsumerWidget {
  const _PendingSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leave = ref.watch(teamLeaveRequestsProvider).valueOrNull ?? const [];
    final adj = ref.watch(teamAdjustmentsProvider).valueOrNull ?? const [];
    final assets = ref.watch(assetRequestsProvider).valueOrNull ?? const [];

    final leavePending = leave.where((r) => r.status == 'pending').length;
    final adjPending = adj.where((r) => r.status == 'pending').length;
    final assetPending =
        assets.where((r) => !r.isApproved && !r.isDeclined).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          _chip(context, 'Leave', leavePending, const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          _chip(context, 'Attendance', adjPending, const Color(0xFFD97706)),
          const SizedBox(width: 8),
          _chip(context, 'Assets', assetPending, const Color(0xFF0891B2)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color,),),
            Text('$label pending',
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),),
          ],
        ),
      ),
    );
  }
}
