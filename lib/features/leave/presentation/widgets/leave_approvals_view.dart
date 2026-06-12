import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/month_filter.dart';
import '../../data/leave_models.dart';
import '../../data/leave_providers.dart';
import 'leave_conflict_dialog.dart';
import 'leave_request_tile.dart';
import 'reject_reason_dialog.dart';

/// Manager/admin leave approval view: team requests grouped by status with
/// approve/reject actions on pending ones. RLS scopes which requests appear.
class LeaveApprovalsView extends ConsumerStatefulWidget {
  const LeaveApprovalsView({super.key});

  @override
  ConsumerState<LeaveApprovalsView> createState() => _LeaveApprovalsViewState();
}

class _LeaveApprovalsViewState extends ConsumerState<LeaveApprovalsView> {
  String _status = 'pending';
  String _month = 'all'; // 'all' or YYYY-MM (by leave start date)

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamLeaveRequestsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(teamLeaveRequestsProvider);
        await ref.read(teamLeaveRequestsProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Could not load requests.')),
            ),
          ],
        ),
        data: (all) {
          final months = {
            for (final r in all) monthKeyFromString(r.startDate),
          }.whereType<String>().toList();
          // Month-filtered set drives BOTH the segment counts and the list.
          final inMonth = all.where((r) =>
              _month == 'all' || monthKeyFromString(r.startDate) == _month,);
          final counts = {
            'pending': inMonth.where((r) => r.status == 'pending').length,
            'approved': inMonth.where((r) => r.status == 'approved').length,
            'rejected': inMonth.where((r) => r.status == 'rejected').length,
          };
          final list =
              inMonth.where((r) => r.status == _status).toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              MonthFilterBar(
                months: months,
                selected: _month,
                onChanged: (m) => setState(() => _month = m),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'pending', label: Text('Pending (${counts['pending']})')),
                  ButtonSegment(value: 'approved', label: Text('Approved (${counts['approved']})')),
                  ButtonSegment(value: 'rejected', label: Text('Rejected (${counts['rejected']})')),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No requests.')),
                )
              else
                for (final r in list)
                  LeaveRequestTile(
                    req: r,
                    showName: true,
                    onApprove:
                        r.status == 'pending' ? () => _approve(r, all) : null,
                    onReject: r.status == 'pending' ? () => _reject(r) : null,
                  ),
            ],
          );
        },
      ),
    );
  }

  /// YYYY-MM-DD string overlap, identical to the web datesOverlap.
  bool _datesOverlap(LeaveRequest a, LeaveRequest b) =>
      a.startDate.compareTo(b.endDate) <= 0 &&
      b.startDate.compareTo(a.endDate) <= 0;

  Future<void> _approve(LeaveRequest r, List<LeaveRequest> all) async {
    // Conflict check (web handleApprove): other PENDING requests by the same
    // employee whose dates overlap this one.
    final conflicts = all
        .where((c) =>
            c.id != r.id &&
            c.userId == r.userId &&
            c.status == 'pending' &&
            _datesOverlap(r, c),)
        .toList();

    if (conflicts.isNotEmpty) {
      final choice = await showLeaveConflictDialog(
        context,
        employeeName: r.employeeName ?? 'Employee',
        current: r,
        conflicts: conflicts,
      );
      if (choice == null || choice == LeaveConflictChoice.cancel) return;
      try {
        await ref.read(leaveRepositoryProvider).approve(r);
        if (choice == LeaveConflictChoice.rejectOthers) {
          for (final c in conflicts) {
            await ref.read(leaveRepositoryProvider).reject(
                  c,
                  'Automatically rejected: conflicting leave request was '
                      'approved for the same dates.',
                );
          }
        }
        ref.invalidate(teamLeaveRequestsProvider);
        _toast(choice == LeaveConflictChoice.rejectOthers
            ? 'Approved; conflicting requests rejected.'
            : 'Leave approved.',);
      } catch (e) {
        _toast('Failed: $e');
      }
      return;
    }

    try {
      await ref.read(leaveRepositoryProvider).approve(r);
      ref.invalidate(teamLeaveRequestsProvider);
      _toast('Leave approved.');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  Future<void> _reject(LeaveRequest r) async {
    final reason = await showRejectReasonDialog(context);
    if (reason == null) return;
    try {
      await ref.read(leaveRepositoryProvider).reject(r, reason);
      ref.invalidate(teamLeaveRequestsProvider);
      _toast('Leave rejected.');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }
}
