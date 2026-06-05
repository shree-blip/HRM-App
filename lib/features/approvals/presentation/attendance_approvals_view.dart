import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/utils/attendance_time.dart';
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
          final counts = {
            'pending': all.where((r) => r.status == 'pending').length,
            'approved': all.where((r) => r.status == 'approved').length,
            'rejected': all.where((r) => r.status == 'rejected').length,
          };
          final list = all.where((r) => r.status == _status).toList();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
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
    final approve = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Override decision'),
        content: const Text('Override the previous review for this request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Reject')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (approve == null) return;
    final comment = await _commentDialog(title: 'Override comment', requireComment: false);
    if (comment == null) return;
    try {
      await ref.read(attendanceRepositoryProvider).overrideAdjustment(
            r.id, approved: approve, comment: comment.isEmpty ? null : comment,);
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
            const SizedBox(height: 6),
            _kv(theme, 'Clock in', '${_t(req.originalClockIn)} → ${_t(req.proposedClockIn)}'),
            _kv(theme, 'Clock out', '${_t(req.originalClockOut)} → ${_t(req.proposedClockOut)}'),
            _kv(theme, 'Break (min)',
                '${req.originalBreakMinutes ?? '—'} → ${req.proposedBreakMinutes ?? '—'}',),
            _kv(theme, 'Pause (min)',
                '${req.originalPauseMinutes ?? '—'} → ${req.proposedPauseMinutes ?? '—'}',),
            if (req.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Reason: ${req.reason}', style: theme.textTheme.bodySmall),
              ),
            if (req.reviewerComment?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Reviewer: ${req.reviewerComment}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
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

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
                width: 110,
                child: Text(k,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),),
            Expanded(child: Text(v, style: theme.textTheme.bodySmall)),
          ],
        ),
      );
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
