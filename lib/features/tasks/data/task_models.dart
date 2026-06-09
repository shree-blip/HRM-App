import 'package:flutter/material.dart';

class TaskAssignee {
  const TaskAssignee({required this.userId, this.name});
  final String userId;
  final String? name;
  String get initials {
    final p = (name ?? '?').trim().split(RegExp(r'\s+'));
    final a = p.isNotEmpty && p[0].isNotEmpty ? p[0][0] : '';
    final b = p.length > 1 && p[1].isNotEmpty ? p[1][0] : '';
    final s = '$a$b';
    return s.isEmpty ? '?' : s.toUpperCase();
  }
}

/// A row from `tasks` (+ assignees + comment count).
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.description,
    this.clientName,
    this.clientId,
    required this.createdBy,
    this.createdByName,
    this.priority = 'medium',
    this.status = 'todo',
    this.dueDate,
    this.timeEstimate,
    this.assignees = const [],
    this.commentCount = 0,
  });

  final String id;
  final String title;
  final String? description;
  final String? clientName;
  final String? clientId;
  final String createdBy;
  final String? createdByName;
  final String priority; // low | medium | high
  final String status; // todo | in-progress | review | done
  final String? dueDate; // YYYY-MM-DD
  final String? timeEstimate;
  final List<TaskAssignee> assignees;
  final int commentCount;
}

/// Kanban columns (exact web order/labels).
const kTaskColumns = <(String id, String title)>[
  ('todo', 'To Do'),
  ('in-progress', 'In Progress'),
  ('review', 'Review'),
  ('done', 'Done'),
];

const kTaskStatuses = ['todo', 'in-progress', 'review', 'done'];
const kTaskPriorities = ['high', 'medium', 'low'];

String taskStatusLabel(String s) => switch (s) {
      'in-progress' => 'In Progress',
      'review' => 'Review',
      'done' => 'Done',
      _ => 'To Do',
    };

IconData taskColumnIcon(String id) => switch (id) {
      'in-progress' => Icons.timelapse_outlined,
      'review' => Icons.schedule_outlined,
      'done' => Icons.check_circle_outline,
      _ => Icons.circle_outlined,
    };

(Color, Color) taskColumnColor(String id) => switch (id) {
      'in-progress' => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
      'review' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'done' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };

Color priorityColor(String p) => switch (p) {
      'high' => const Color(0xFFDC2626),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF6B7280),
    };

/// "MMM d" or "No date" (web dueDate display).
String dueDisplay(String? due) {
  if (due == null || due.isEmpty) return 'No date';
  final d = DateTime.tryParse(due);
  if (d == null) return due;
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[d.month - 1]} ${d.day}';
}
