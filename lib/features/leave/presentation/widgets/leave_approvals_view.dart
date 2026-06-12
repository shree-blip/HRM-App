import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/month_filter.dart';
import '../../data/leave_csv.dart';
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
  String _employee = 'all'; // 'all' or user_id
  String _leaveType = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    // Live refresh on leave_requests changes (web "leave-changes" channel).
    ref.watch(leaveRealtimeProvider);
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
          // Unique employees + leave types for the filter dropdowns (web parity).
          final employees = <String, String>{
            for (final r in all) r.userId: r.employeeName ?? 'Employee',
          };
          final leaveTypes =
              {for (final r in all) r.leaveType}.toList()..sort();

          // Apply month + employee + type + search, then status.
          bool matches(LeaveRequest r) {
            if (_month != 'all' && monthKeyFromString(r.startDate) != _month) {
              return false;
            }
            if (_employee != 'all' && r.userId != _employee) return false;
            if (_leaveType != 'all' && r.leaveType != _leaveType) return false;
            if (_search.trim().isNotEmpty) {
              final q = _search.toLowerCase();
              final hay = '${r.employeeName ?? ''} ${r.leaveType} '
                      '${r.reason ?? ''}'
                  .toLowerCase();
              if (!hay.contains(q)) return false;
            }
            return true;
          }

          final filtered = all.where(matches);
          final counts = {
            'pending': filtered.where((r) => r.status == 'pending').length,
            'approved': filtered.where((r) => r.status == 'approved').length,
            'rejected': filtered.where((r) => r.status == 'rejected').length,
          };
          final list = filtered.where((r) => r.status == _status).toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              MonthFilterBar(
                months: months,
                selected: _month,
                onChanged: (m) => setState(() => _month = m),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search name / type / reason',
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _employee,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Employee', isDense: true,),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All employees')),
                      for (final e in employees.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _employee = v ?? 'all'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _leaveType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Leave type', isDense: true,),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All types')),
                      for (final t in leaveTypes)
                        DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _leaveType = v ?? 'all'),
                  ),
                ),
              ],),
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Export CSV'),
                  onPressed: list.isEmpty
                      ? null
                      : () => shareCsv('$_status-leaves', leaveApprovalsCsv(list)),
                ),
              ),
              const SizedBox(height: 4),
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
