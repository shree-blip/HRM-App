import 'package:flutter/material.dart';

/// A row from the `documents` table. New rows store a Google Drive link in
/// `drive_link`; legacy rows store a Supabase storage path in `file_path`.
class HrDocument {
  const HrDocument({
    required this.id,
    required this.name,
    this.filePath,
    this.driveLink,
    this.fileType,
    this.category,
    this.status,
    this.employeeId,
    this.leaveRequestId,
    this.uploadedBy,
    this.createdAt,
    this.updatedAt,
    this.uploaderName,
    this.assigneeName,
  });

  final String id;
  final String name;
  final String? filePath; // legacy storage path
  final String? driveLink; // Google Drive share URL (new)
  final String? fileType; // 'drive' for link docs, or extension for legacy
  final String? category;
  final String? status;
  final String? employeeId;
  final String? leaveRequestId;
  final String? uploadedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? uploaderName;
  final String? assigneeName;

  bool get hasDriveLink => driveLink != null && driveLink!.trim().isNotEmpty;
  bool get hasLegacyFile => filePath != null && filePath!.trim().isNotEmpty;

  HrDocument copyWith({String? uploaderName, String? assigneeName}) => HrDocument(
        id: id, name: name, filePath: filePath, driveLink: driveLink,
        fileType: fileType, category: category, status: status,
        employeeId: employeeId, leaveRequestId: leaveRequestId,
        uploadedBy: uploadedBy, createdAt: createdAt, updatedAt: updatedAt,
        uploaderName: uploaderName ?? this.uploaderName,
        assigneeName: assigneeName ?? this.assigneeName,
      );

  factory HrDocument.fromMap(Map<String, dynamic> m) => HrDocument(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        filePath: m['file_path'] as String?,
        driveLink: m['drive_link'] as String?,
        fileType: m['file_type'] as String?,
        category: m['category'] as String?,
        status: m['status'] as String?,
        employeeId: m['employee_id'] as String?,
        leaveRequestId: m['leave_request_id'] as String?,
        uploadedBy: m['uploaded_by'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
            : null,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)?.toUtc()
            : null,
      );
}

/// Document categories (exact strings from the web app).
const kDocCategories = ['Contracts', 'Policies', 'Compliance', 'Leave Evidence'];
const kPrivateCategories = ['Compliance', 'Contracts'];
const kLeaveEvidenceCategory = 'Leave Evidence';

bool isPrivateCategory(String? c) => kPrivateCategories.contains(c);
bool isLeaveEvidenceCategory(String? c) => c == kLeaveEvidenceCategory;
bool isRestrictedCategory(String? c) =>
    isPrivateCategory(c) || isLeaveEvidenceCategory(c);

String? visibilityTooltip(String? c) {
  if (isLeaveEvidenceCategory(c)) {
    return 'Restricted - Visible to uploader, manager, line manager, VP, and admins';
  }
  if (isPrivateCategory(c)) {
    return 'Private - Visible only to the uploader, the assigned employee, admins, and CEO';
  }
  return null;
}

/// Category info text shown in the add dialog (web CATEGORY_INFO).
String categoryInfo(String c) => switch (c) {
      'Contracts' => 'Private - Visible to you, the assigned employee, VP, and admins.',
      'Policies' => 'Public - Visible to all employees',
      'Compliance' => 'Private - Visible only to the uploader, the assigned employee, admins, and CEO.',
      'Leave Evidence' => 'Restricted - Visible to you, managers, line managers, VPs, and admins',
      _ => '',
    };

IconData categoryIcon(String? category) => switch (category) {
      'Contracts' => Icons.description_outlined,
      'Policies' => Icons.policy_outlined,
      'Compliance' => Icons.verified_user_outlined,
      'Leave Evidence' => Icons.event_available_outlined,
      _ => Icons.folder_open_outlined,
    };

/// Status badge colors (mirrors the web color-coding).
(Color bg, Color fg) statusColors(String? status) => switch (status) {
      'signed' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'approved' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      'active' => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
      'draft' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'completed' => (const Color(0xFFCFFAFE), const Color(0xFF0891B2)),
      _ => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };
