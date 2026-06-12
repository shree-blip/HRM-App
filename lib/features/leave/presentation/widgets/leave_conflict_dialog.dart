import 'package:flutter/material.dart';

import '../../data/leave_models.dart';

/// Outcome of the conflict dialog, mirroring the web LeaveConflictDialog
/// actions (Cancel / Approve This & Reject Others / Approve Without Resolving).
enum LeaveConflictChoice { cancel, rejectOthers, approveAnyway }

/// Shown when approving a leave request that overlaps the employee's other
/// pending requests — exact port of the web LeaveConflictDialog.
Future<LeaveConflictChoice?> showLeaveConflictDialog(
  BuildContext context, {
  required String employeeName,
  required LeaveRequest current,
  required List<LeaveRequest> conflicts,
}) {
  return showDialog<LeaveConflictChoice>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget row(LeaveRequest r, {required bool warn}) {
        final color = warn ? const Color(0xFFD97706) : theme.colorScheme.primary;
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text('${r.startDate} – ${r.endDate}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13,),),
                  ),
                  Text('${_fmtDays(r.days)} day${r.days == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: color,),),
                ],
              ),
              Text(r.leaveType,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            ],
          ),
        );
      }

      return AlertDialog(
        title: const Text('⚠️ Conflicting Leave Requests'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$employeeName has multiple pending leave requests with '
                'overlapping dates. Clarify which dates they prefer before '
                'final approval.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text("Request you're approving:",
                  style: theme.textTheme.labelMedium,),
              row(current, warn: false),
              const SizedBox(height: 12),
              Text('Conflicting pending request(s):',
                  style: theme.textTheme.labelMedium,),
              for (final c in conflicts) row(c, warn: true),
            ],
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, LeaveConflictChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, LeaveConflictChoice.approveAnyway),
            child: const Text('Approve Without Resolving'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, LeaveConflictChoice.rejectOthers),
            child: const Text('Approve This & Reject Others'),
          ),
        ],
      );
    },
  );
}

String _fmtDays(num d) =>
    d == d.roundToDouble() ? d.toInt().toString() : d.toString();
