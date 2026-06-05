import 'package:flutter/material.dart';

/// Circular avatar that shows the employee photo when available, otherwise
/// their initials on a tinted background.
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({
    super.key,
    required this.initials,
    this.url,
    this.radius = 22,
  });

  final String initials;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary.withValues(alpha: 0.12),
      foregroundImage: hasUrl ? NetworkImage(url!) : null,
      child: Text(
        initials,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

/// Small colored status pill for active / probation / inactive.
class EmployeeStatusChip extends StatelessWidget {
  const EmployeeStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'inactive' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      'probation' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      _ => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
