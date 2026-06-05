import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../attendance/data/attendance_providers.dart';
import '../../leave/data/leave_providers.dart';
import '../../leave/presentation/widgets/leave_approvals_view.dart';
import '../../support/data/asset_providers.dart';
import 'asset_approvals_view.dart';
import 'attendance_approvals_view.dart';

/// Unified Approvals page (Phase 6): Leave, Attendance adjustments, and Asset
/// requests, with a pending summary. Matching the web app, all three tabs are
/// always shown to anyone who reaches this page (the drawer/route gates who
/// gets here); RLS scopes the data and per-action role checks gate approvals.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Approvals'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Leave'),
              Tab(text: 'Attendance'),
              Tab(text: 'Assets'),
            ],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/approvals'),
        body: const Column(
          children: [
            _PendingSummary(),
            Expanded(
              child: TabBarView(
                children: [
                  LeaveApprovalsView(),
                  AttendanceApprovalsView(),
                  AssetApprovalsView(),
                ],
              ),
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
