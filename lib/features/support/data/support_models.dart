import 'package:flutter/material.dart';

/// ── Bug reports ─────────────────────────────────────────
class BugReport {
  const BugReport({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    this.status,
    this.reporterName,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final String description;
  final String? status;
  final String? reporterName;
  final DateTime? createdAt;

  BugReport withReporter(String? name) => BugReport(
        id: id, userId: userId, title: title, description: description,
        status: status, reporterName: name, createdAt: createdAt,
      );

  factory BugReport.fromMap(Map<String, dynamic> m) => BugReport(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        status: m['status'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
            : null,
      );
}

const kBugStatuses = ['open', 'in_progress', 'resolved', 'closed'];

(Color, Color) bugStatusColors(String? s) => switch (s) {
      'open' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      'in_progress' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'resolved' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'closed' => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };

/// ── Grievances ──────────────────────────────────────────
class Grievance {
  const Grievance({
    required this.id,
    required this.userId,
    required this.title,
    this.category,
    this.priority,
    this.details,
    this.status,
    this.isAnonymous = false,
    this.anonymousVisibility = 'nobody',
    this.assignedTo,
    this.submitterName,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final String? category;
  final String? priority;
  final String? details;
  final String? status;
  final bool isAnonymous;
  final String anonymousVisibility; // nobody | hr_admin | vp_hr
  final String? assignedTo;
  final String? submitterName;
  final DateTime? createdAt;

  Grievance withSubmitter(String? name) => Grievance(
        id: id, userId: userId, title: title, category: category,
        priority: priority, details: details, status: status,
        isAnonymous: isAnonymous, anonymousVisibility: anonymousVisibility,
        assignedTo: assignedTo, submitterName: name, createdAt: createdAt,
      );

  factory Grievance.fromMap(Map<String, dynamic> m) => Grievance(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: (m['title'] ?? '') as String,
        category: m['category'] as String?,
        priority: m['priority'] as String?,
        details: m['details'] as String?,
        status: m['status'] as String?,
        isAnonymous: m['is_anonymous'] == true,
        anonymousVisibility: (m['anonymous_visibility'] ?? 'nobody') as String,
        assignedTo: m['assigned_to'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
            : null,
      );

  /// Submitter display honoring anonymity + viewer role.
  String displayName({
    required String viewerUid,
    required bool isAdmin,
    required bool isVp,
  }) {
    if (!isAnonymous) return submitterName ?? 'Employee';
    if (userId == viewerUid) return 'You (Anonymous)';
    if (anonymousVisibility == 'hr_admin' && isAdmin) {
      return '${submitterName ?? 'Employee'} (Anonymous to others)';
    }
    if (anonymousVisibility == 'vp_hr' && (isVp || isAdmin)) {
      return '${submitterName ?? 'Employee'} (Anonymous to others)';
    }
    return 'Anonymous';
  }
}

const kGrievanceCategories = [
  'Harassment', 'Payroll', 'Manager Issue', 'Workload', 'Policy', 'Safety', 'Other',
];
const kGrievancePriorities = ['Low', 'Medium', 'High', 'Urgent'];
const kGrievanceStatuses = [
  'submitted', 'in_review', 'need_info', 'resolved', 'closed', 'escalated',
];
const kAnonymousVisibility = <(String, String)>[
  ('nobody', 'Anonymous to everyone'),
  ('hr_admin', 'Visible to HR/Admin only'),
  ('vp_hr', 'Visible to VP & HR'),
];

String grievanceStatusLabel(String? s) => switch (s) {
      'submitted' => 'Submitted',
      'in_review' => 'In Review',
      'need_info' => 'Need Info',
      'resolved' => 'Resolved',
      'closed' => 'Closed',
      'escalated' => 'Escalated',
      _ => s ?? '—',
    };

(Color, Color) grievanceStatusColors(String? s) => switch (s) {
      'submitted' => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
      'in_review' => (const Color(0xFFEDE9FE), const Color(0xFF7C3AED)),
      'need_info' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'resolved' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'closed' => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
      'escalated' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };

(Color, Color) priorityColors(String? p) => switch (p) {
      'Low' => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
      'Medium' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'High' => (const Color(0xFFFFEDD5), const Color(0xFFEA580C)),
      'Urgent' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };
