import 'package:flutter/material.dart';

import '../data/onboarding_models.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "MMM d, yyyy" from a 'YYYY-MM-DD' (or ISO) string.
String onbDate(String value) {
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

Widget onbStatusBadge(BuildContext context, String status) {
  Color c;
  switch (status) {
    case 'completed':
      c = Colors.green.shade700;
    case 'in-progress':
      c = Colors.blue.shade700;
    case 'cancelled':
      c = Theme.of(context).colorScheme.onSurfaceVariant;
    default:
      c = Colors.orange.shade800; // pending
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.4))),
    child: Text(onboardingStatusLabel(status), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

class OnbEmptyState extends StatelessWidget {
  const OnbEmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],),
      ),
    );
  }
}
