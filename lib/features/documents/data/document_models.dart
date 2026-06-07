import 'package:flutter/material.dart';

/// A row from the `documents` table. The Drive link is stored in `file_path`
/// (no schema change); legacy rows hold a Supabase storage path there instead.
class HrDocument {
  const HrDocument({
    required this.id,
    required this.name,
    required this.filePath,
    this.fileType,
    this.category,
    this.status,
    this.employeeId,
    this.uploadedBy,
    this.createdAt,
    this.uploaderName,
    this.assigneeName,
  });

  final String id;
  final String name;
  final String filePath; // Google Drive URL (new) or storage path (legacy)
  final String? fileType;
  final String? category;
  final String? status;
  final String? employeeId;
  final String? uploadedBy;
  final DateTime? createdAt;
  final String? uploaderName;
  final String? assigneeName;

  /// True when `file_path` is an external link (Google Drive etc.).
  bool get isLink =>
      filePath.startsWith('http://') || filePath.startsWith('https://');

  HrDocument copyWith({String? uploaderName, String? assigneeName}) => HrDocument(
        id: id,
        name: name,
        filePath: filePath,
        fileType: fileType,
        category: category,
        status: status,
        employeeId: employeeId,
        uploadedBy: uploadedBy,
        createdAt: createdAt,
        uploaderName: uploaderName ?? this.uploaderName,
        assigneeName: assigneeName ?? this.assigneeName,
      );

  factory HrDocument.fromMap(Map<String, dynamic> m) => HrDocument(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        filePath: (m['file_path'] ?? '') as String,
        fileType: m['file_type'] as String?,
        category: m['category'] as String?,
        status: m['status'] as String?,
        employeeId: m['employee_id'] as String?,
        uploadedBy: m['uploaded_by'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
            : null,
      );
}

/// Document categories (exact strings from the web app).
const kDocCategories = ['Contracts', 'Policies', 'Compliance', 'Leave Evidence'];

/// Document "type" stored in file_type. Drive links default to `link`.
const kDocTypes = <(String, String)>[
  ('link', 'Drive link'),
  ('pdf', 'PDF'),
  ('docx', 'Document'),
  ('xlsx', 'Spreadsheet'),
  ('image', 'Image'),
];

String docTypeLabel(String? v) {
  for (final t in kDocTypes) {
    if (t.$1 == v) return t.$2;
  }
  return v == null || v.isEmpty ? 'Link' : v;
}

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

/// Whether a category is "private/restricted" (shown with a lock hint).
bool isRestrictedCategory(String? c) =>
    c == 'Contracts' || c == 'Compliance' || c == 'Leave Evidence';
