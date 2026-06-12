import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/utils/attendance_time.dart';
import '../../../core/widgets/month_filter.dart';
import '../../attendance/data/adjustment_models.dart';
import '../../attendance/data/attendance_providers.dart';

/// Attendance adjustment approvals (manager review + VP/Admin override).
class AttendanceApprovalsView extends ConsumerStatefulWidget {
  const AttendanceApprovalsView({super.key});

  @override
  ConsumerState<AttendanceApprovalsView> createState() =>
      _AttendanceApprovalsViewState();
}

class _AttendanceApprovalsViewState
    extends ConsumerState<AttendanceApprovalsView> {
  String _status = 'pending';
  String _month = 'all'; // 'all' or YYYY-MM (by request created date)

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamAdjustmentsProvider);
    final canOverride = ref.watch(authControllerProvider.select((s) => s.isVp));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(teamAdjustmentsProvider);
        await ref.read(teamAdjustmentsProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(children: const [
          Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Could not load.'))),
        ],),
        data: (all) {
          final months = {
            for (final r in all) monthKeyFromDate(r.createdAt),
          }.whereType<String>().toList();
          final inMonth = all.where((r) =>
              _month == 'all' || monthKeyFromDate(r.createdAt) == _month,);
          final counts = {
            'pending': inMonth.where((r) => r.status == 'pending').length,
            'approved': inMonth.where((r) => r.status == 'approved').length,
            'rejected': inMonth.where((r) => r.status == 'rejected').length,
          };
          final list = inMonth.where((r) => r.status == _status).toList();
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
                  _AdjustmentCard(
                    req: r,
                    onApprove: r.status == 'pending' ? () => _review(r, true) : null,
                    onReject: r.status == 'pending' ? () => _review(r, false) : null,
                    onOverride: (r.status != 'pending' && canOverride)
                        ? () => _override(r)
                        : null,
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _review(AdjustmentRequest r, bool approved) async {
    final comment = await _commentDialog(
      title: approved ? 'Approve adjustment' : 'Reject adjustment',
      requireComment: !approved,
    );
    if (comment == null) return; // cancelled
    try {
      await ref.read(attendanceRepositoryProvider).reviewAdjustment(
            r.id, approved: approved, comment: comment.isEmpty ? null : comment,);
      ref.invalidate(teamAdjustmentsProvider);
      _toast(approved ? 'Approved.' : 'Rejected.');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  Future<void> _override(AdjustmentRequest r) async {
    // Rich override dialog: original vs proposed values, the current
    // decision + reviewer comment, and an override comment field.
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        String t(DateTime? d) => d == null ? '—' : NptTime.formatTime(d);
        Widget row(String label, String original, String proposed) {
          final changed = original != proposed;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: 78,
                child: Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              ),
              Expanded(
                child: Text(original,
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: changed ? TextDecoration.lineThrough : null,
                      color: changed ? theme.colorScheme.onSurfaceVariant : null,
                    ),),
              ),
              const Icon(Icons.arrow_forward, size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(proposed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: changed ? FontWeight.w700 : FontWeight.normal,
                      color: changed ? theme.colorScheme.primary : null,
                    ),),
              ),
            ],),
          );
        }

        return AlertDialog(
          title: const Text('Override decision'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(r.requesterName ?? 'Employee',
                        style: const TextStyle(fontWeight: FontWeight.w600),),
                  ),
                  _StatusChip(status: r.overrideStatus ?? r.status),
                ],),
                const SizedBox(height: 10),
                Row(children: [
                  const SizedBox(width: 78),
                  Expanded(
                    child: Text('Original',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,),),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text('Proposed',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,),),
                  ),
                ],),
                row('Clock in', t(r.originalClockIn), t(r.proposedClockIn)),
                row('Clock out', t(r.originalClockOut), t(r.proposedClockOut)),
                row('Break', '${r.originalBreakMinutes ?? 0}m',
                    '${r.proposedBreakMinutes ?? 0}m',),
                row('Pause', '${r.originalPauseMinutes ?? 0}m',
                    '${r.proposedPauseMinutes ?? 0}m',),
                if (r.reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Reason: ${r.reason}', style: theme.textTheme.bodySmall),
                ],
                if (r.reviewerComment?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Reviewer: ${r.reviewerComment}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,),),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Override comment (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            // One clean responsive row: Approve + Reject on the left,
            // Cancel on the right. Compact buttons so nothing overflows on
            // narrow screens.
            SizedBox(
              width: double.maxFinite,
              child: Row(
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Reject'),
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final comment = controller.text.trim();
    try {
      await ref.read(attendanceRepositoryProvider).overrideAdjustment(
            r.id, approved: result, comment: comment.isEmpty ? null : comment,);
      ref.invalidate(teamAdjustmentsProvider);
      _toast('Override saved.');
    } catch (e) {
      _toast('Failed: $e');
    }
  }

  Future<String?> _commentDialog({
    required String title,
    required bool requireComment,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: requireComment ? 'Comment *' : 'Comment (optional)',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final t = controller.text.trim();
                  if (requireComment && t.isEmpty) {
                    setState(() => error = 'A comment is required.');
                    return;
                  }
                  Navigator.pop(ctx, t);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }
}

class _AdjustmentCard extends StatelessWidget {
  const _AdjustmentCard({
    required this.req,
    this.onApprove,
    this.onReject,
    this.onOverride,
  });
  final AdjustmentRequest req;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onOverride;

  String _t(DateTime? d) => d == null ? '—' : NptTime.formatTime(d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cmp(String label, String original, String proposed) {
      final changed = original != proposed;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 78,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          ),
          Expanded(
            child: Text(original,
                style: theme.textTheme.bodySmall?.copyWith(
                  decoration: changed ? TextDecoration.lineThrough : null,
                  color: changed ? theme.colorScheme.onSurfaceVariant : null,
                ),),
          ),
          const Icon(Icons.arrow_forward, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(proposed,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: changed ? FontWeight.w700 : FontWeight.normal,
                  color: changed ? theme.colorScheme.primary : null,
                ),),
          ),
        ],),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(req.requesterName ?? 'Employee',
                      style: const TextStyle(fontWeight: FontWeight.bold),),
                ),
                _StatusChip(status: req.overrideStatus ?? req.status),
              ],
            ),
            if (req.createdAt != null)
              Text('Requested ${NptTime.formatDateShort(req.createdAt!)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            const SizedBox(height: 8),
            // Original / Proposed comparison (full details for every status,
            // not just proposed values).
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                const SizedBox(width: 78),
                Expanded(
                  child: Text('Original',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,),),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Text('Proposed',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,),),
                ),
              ],),
            ),
            cmp('Clock in', _t(req.originalClockIn), _t(req.proposedClockIn)),
            cmp('Clock out', _t(req.originalClockOut), _t(req.proposedClockOut)),
            cmp('Break', '${req.originalBreakMinutes ?? 0}m',
                '${req.proposedBreakMinutes ?? 0}m',),
            cmp('Pause', '${req.originalPauseMinutes ?? 0}m',
                '${req.proposedPauseMinutes ?? 0}m',),
            if (req.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Reason: ${req.reason}', style: theme.textTheme.bodySmall),
              ),
            if (req.reviewerComment?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Reviewer: ${req.reviewerComment}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,),),
              ),
            if (onApprove != null || onReject != null || onOverride != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onOverride != null)
                      OutlinedButton(onPressed: onOverride, child: const Text('Override')),
                    if (onReject != null) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),),
                        onPressed: onReject,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (onApprove != null)
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        onPressed: onApprove,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'approved' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'rejected' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      _ => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),),
    );
  }
}
