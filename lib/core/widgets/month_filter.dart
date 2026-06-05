import 'package:flutter/material.dart';

/// Helpers + UI for month-wise filtering of approval lists (mirrors the React
/// Approvals page's Month selector).

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 'YYYY-MM-DD...' -> 'YYYY-MM' (works for date keys and ISO timestamps).
String? monthKeyFromString(String? s) {
  if (s == null || s.length < 7) return null;
  return s.substring(0, 7);
}

String? monthKeyFromDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// '2026-06' -> 'Jun 2026'
String monthLabel(String ym) {
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final m = int.tryParse(parts[1]) ?? 0;
  if (m < 1 || m > 12) return ym;
  return '${_months[m - 1]} ${parts[0]}';
}

/// A "Month" dropdown ("All months" + the supplied YYYY-MM keys, newest first).
class MonthFilterBar extends StatelessWidget {
  const MonthFilterBar({
    super.key,
    required this.months,
    required this.selected,
    required this.onChanged,
  });

  final List<String> months; // YYYY-MM keys
  final String selected; // 'all' or a YYYY-MM key
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = [...months]..sort((a, b) => b.compareTo(a));
    return Row(
      children: [
        Icon(Icons.calendar_month, size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,),
        const SizedBox(width: 8),
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Month',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All months')),
                  for (final m in sorted)
                    DropdownMenuItem(value: m, child: Text(monthLabel(m))),
                ],
                onChanged: (v) => onChanged(v ?? 'all'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
