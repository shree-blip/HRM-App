import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/employee.dart';
import '../data/employees_providers.dart';
import '../data/team_models.dart';

/// Read-only leave summary for an employee (parity with the web Leave dialog —
/// balances + progress bars; admin/VP manual-edit is web-only for now).
Future<void> showLeaveSummary(BuildContext context, WidgetRef ref, EmployeeDirectoryItem e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LeaveSheet(employee: e),
  );
}

class _LeaveSheet extends ConsumerStatefulWidget {
  const _LeaveSheet({required this.employee});
  final EmployeeDirectoryItem employee;
  @override
  ConsumerState<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends ConsumerState<_LeaveSheet> {
  List<LeaveBalance> _balances = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(employeesRepositoryProvider);
    try {
      final userId = await repo.userIdForProfile(widget.employee.profileId);
      if (userId != null) {
        _balances = await repo.leaveBalances(userId, DateTime.now());
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.employee;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.calendar_month_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Leave — ${e.fullName}', style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
          ],),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_balances.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.calendar_month_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('No leave data available', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],),
              ),
            )
          else
            ..._balances.map((lb) => _balanceCard(context, lb)),
        ],
      ),
    );
  }

  Widget _balanceCard(BuildContext context, LeaveBalance lb) {
    final theme = Theme.of(context);
    final pct = lb.totalDays > 0 ? (lb.usedDays / lb.totalDays).clamp(0.0, 1.0) : 0.0;
    final over = lb.usedDays > lb.totalDays;
    final barColor = lb.totalDays > 0 && lb.usedDays >= lb.totalDays
        ? theme.colorScheme.error
        : (lb.totalDays > 0 && lb.usedDays / lb.totalDays > 0.5 ? Colors.amber.shade700 : theme.colorScheme.primary);
    String fmt(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lb.leaveType, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(fmt(lb.remainingDays), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text('/ ${fmt(lb.totalDays)} remaining', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (over) ...[
                const SizedBox(width: 6),
                Text('+${fmt(lb.usedDays - lb.totalDays)} over', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
              ],
            ],),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: theme.colorScheme.surfaceContainerHighest, color: barColor),
            ),
            const SizedBox(height: 4),
            Text('${fmt(lb.usedDays)} used', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
