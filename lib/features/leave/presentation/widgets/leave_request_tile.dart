import 'package:flutter/material.dart';

import '../../data/leave_models.dart';

/// One leave request row: type, dates, days, status, reason. Optionally shows
/// the employee name (manager view) and approve/reject actions.
class LeaveRequestTile extends StatelessWidget {
  const LeaveRequestTile({
    super.key,
    required this.req,
    this.showName = false,
    this.onApprove,
    this.onReject,
  });

  final LeaveRequest req;
  final bool showName;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysText = req.days == req.days.roundToDouble()
        ? '${req.days.toInt()}'
        : '${req.days}';
    final dateRange = req.startDate == req.endDate
        ? req.startDate
        : '${req.startDate} → ${req.endDate}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showName && req.employeeName != null)
                        Text(req.employeeName!,
                            style: const TextStyle(fontWeight: FontWeight.bold),),
                      Text(req.leaveType,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),),
                      const SizedBox(height: 2),
                      Text(
                        '$dateRange  ·  $daysText ${req.days == 1 ? 'day' : 'days'}'
                        '${req.isHalfDay ? ' (half)' : ''}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: req.status),
              ],
            ),
            if (req.cleanReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(req.cleanReason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,),
              ),
            if (req.deductionType != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Deduction: ${req.deductionType}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              ),
            if (req.status == 'rejected' && req.rejectionReason?.isNotEmpty == true)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Reason: ${req.rejectionReason}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFDC2626),),),
              ),
            if (onApprove != null || onReject != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onReject != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),),
                        onPressed: onReject,
                      ),
                    const SizedBox(width: 8),
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
      'cancelled' => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
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
