import 'package:flutter/material.dart';

/// Color / icon / label config for live-attendance status codes, mirroring the
/// web STATUS + EVENT_LABELS maps.
class LiveStatusStyle {
  const LiveStatusStyle(this.color, this.bg, this.icon, this.label);
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;

  static const _map = <String, LiveStatusStyle>{
    'IN': LiveStatusStyle(Color(0xFF059669), Color(0xFFD1FAE5), Icons.work_outline, 'Clocked In'),
    'OUT': LiveStatusStyle(Color(0xFF64748B), Color(0xFFE2E8F0), Icons.logout, 'Clocked Out'),
    'BRS': LiveStatusStyle(Color(0xFFD97706), Color(0xFFFEF3C7), Icons.coffee_outlined, 'On Break'),
    'BRE': LiveStatusStyle(Color(0xFF0D9488), Color(0xFFCCFBF1), Icons.work_outline, 'Resumed'),
    'PAUSE': LiveStatusStyle(Color(0xFF2563EB), Color(0xFFDBEAFE), Icons.pause, 'Paused'),
    'CONT': LiveStatusStyle(Color(0xFF0891B2), Color(0xFFCFFAFE), Icons.work_outline, 'Continued'),
    '—': LiveStatusStyle(Color(0xFF9CA3AF), Color(0xFFF3F4F6), Icons.circle_outlined, 'Not Started'),
  };

  static LiveStatusStyle of(String code) => _map[code] ?? _map['—']!;
}
