import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/dashboard_providers.dart';
import '../../data/dashboard_repository.dart';
import 'section_card.dart';

/// Recent leave requests (mirrors web LeaveWidget). Employees see their own;
/// managers see team requests (RLS-scoped). Read-only.
class LeaveRequestsCard extends ConsumerWidget {
  const LeaveRequestsCard({super.key, required this.isManager});
  final bool isManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentLeaveProvider);
    return SectionCard(
      icon: Icons.beach_access_outlined,
      title: isManager ? 'Leave Requests' : 'My Leave Requests',
      onViewAll: () => context.go(isManager ? '/approvals' : '/leave'),
      child: async.when(
        loading: () => const SectionLoading(),
        error: (_, __) => const SectionError('Could not load leave requests.'),
        data: (items) {
          if (items.isEmpty) return const SectionEmpty('No leave requests.');
          return Column(
            children: [
              for (final l in items.take(isManager ? 5 : 3))
                _LeaveRow(item: l, showName: isManager),
            ],
          );
        },
      ),
    );
  }
}

class _LeaveRow extends StatelessWidget {
  const _LeaveRow({required this.item, required this.showName});
  final LeaveItem item;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateRange = item.startDate == item.endDate
        ? item.startDate
        : '${item.startDate} → ${item.endDate}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showName && item.employeeName.isNotEmpty
                      ? '${item.employeeName} · ${item.leaveType}'
                      : item.leaveType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '$dateRange  ·  ${_fmtDays(item.days, item.isHalfDay)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(status: item.status),
        ],
      ),
    );
  }

  static String _fmtDays(num days, bool half) {
    if (half) return 'Half day';
    final d = days == days.roundToDouble() ? days.toInt().toString() : '$days';
    return '$d ${days == 1 ? 'day' : 'days'}';
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
      _ => (const Color(0xFFFEF3C7), const Color(0xFFD97706)), // pending
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
