import 'package:flutter/material.dart';

/// A row from the `notifications` table.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    this.type,
    this.link,
    this.isRead = false,
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final String message;
  final String? type;
  final String? link;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;

  NotificationItem copyWith({bool? isRead, DateTime? readAt}) => NotificationItem(
        id: id, userId: userId, title: title, message: message, type: type,
        link: link, isRead: isRead ?? this.isRead, readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );

  factory NotificationItem.fromMap(Map<String, dynamic> m) => NotificationItem(
        id: m['id'] as String,
        userId: (m['user_id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        message: (m['message'] ?? '') as String,
        type: m['type'] as String?,
        link: m['link'] as String?,
        isRead: m['is_read'] == true,
        readAt: m['read_at'] != null ? DateTime.tryParse(m['read_at'] as String)?.toUtc() : null,
        createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'] as String)?.toUtc() : null,
      );
}

/// Icon + color per notification type (mirrors the web getNotificationIcon).
(IconData, Color) notificationIcon(String? type) => switch (type) {
      'leave' => (Icons.event_outlined, const Color(0xFF2563EB)),
      'task' => (Icons.description_outlined, const Color(0xFFD97706)),
      'onboarding' => (Icons.group_outlined, const Color(0xFF16A34A)),
      'payroll' => (Icons.schedule_outlined, const Color(0xFF0D9488)),
      'announcement' => (Icons.campaign_outlined, const Color(0xFF0D9488)),
      _ => (Icons.notifications_none, const Color(0xFF6B7280)),
    };

/// "x minutes/hours/days ago" (no intl dependency).
String timeAgo(DateTime? utc) {
  if (utc == null) return '';
  final diff = DateTime.now().toUtc().difference(utc);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final w = diff.inDays ~/ 7;
  if (w < 5) return '${w}w ago';
  final mo = diff.inDays ~/ 30;
  if (mo < 12) return '${mo}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}
