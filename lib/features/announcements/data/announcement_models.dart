import 'package:flutter/material.dart';

/// A row from `announcements` (same table the dashboard widget reads).
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.type = 'info',
    this.isPinned = false,
    this.isActive = true,
    this.expiresAt,
    this.createdBy,
    this.createdAt,
    this.publisherName,
  });

  final String id;
  final String title;
  final String content;
  final String type; // info | important | event
  final bool isPinned;
  final bool isActive;
  final DateTime? expiresAt;
  final String? createdBy;
  final DateTime? createdAt;
  final String? publisherName;

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());

  Announcement withPublisher(String? name) => Announcement(
        id: id, title: title, content: content, type: type, isPinned: isPinned,
        isActive: isActive, expiresAt: expiresAt, createdBy: createdBy,
        createdAt: createdAt, publisherName: name,
      );

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as String,
        title: (m['title'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        type: (m['type'] ?? 'info') as String,
        isPinned: m['is_pinned'] == true,
        isActive: m['is_active'] != false,
        expiresAt: m['expires_at'] != null
            ? DateTime.tryParse(m['expires_at'] as String)?.toUtc()
            : null,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
            : null,
      );
}

const kAnnouncementTypes = <(String, String)>[
  ('info', 'Info'),
  ('important', 'Important'),
  ('event', 'Event'),
];

/// Expiry duration presets (label -> Duration?; null = no expiry).
const kAnnouncementDurations = <(String, Duration?)>[
  ('No expiry', null),
  ('1 hour', Duration(hours: 1)),
  ('4 hours', Duration(hours: 4)),
  ('1 day', Duration(days: 1)),
  ('3 days', Duration(days: 3)),
  ('1 week', Duration(days: 7)),
];

(Color, Color) announcementTypeColors(String type) => switch (type) {
      'important' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      'event' => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF4B5563)),
    };
