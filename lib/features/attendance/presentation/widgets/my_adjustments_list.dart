import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/attendance_time.dart';
import '../../data/adjustment_models.dart';
import '../../data/attendance_providers.dart';

/// "My Adjustment Requests" — the current user's submitted corrections and
/// their status (read-only). Hidden when there are none.
class MyAdjustmentsList extends ConsumerWidget {
  const MyAdjustmentsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(myAdjustmentsProvider);
    return async.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text('My Adjustment Requests',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),),
            const SizedBox(height: 8),
            for (final r in items) _RequestTile(req: r),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.req});
  final AdjustmentRequest req;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inT = req.proposedClockIn != null
        ? NptTime.formatTime(req.proposedClockIn!)
        : '—';
    final outT = req.proposedClockOut != null
        ? NptTime.formatTime(req.proposedClockOut!)
        : '—';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    req.createdAt != null
                        ? NptTime.formatDateShort(req.createdAt!)
                        : 'Request',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _StatusChip(status: req.effectiveStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text('Proposed: $inT → $outT  ·  '
                'break ${req.proposedBreakMinutes ?? 0}m, pause ${req.proposedPauseMinutes ?? 0}m',
                style: theme.textTheme.bodySmall,),
            if (req.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Reason: ${req.reason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,),),
              ),
            if (req.reviewerComment?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Reviewer: ${req.reviewerComment}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,),),
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
