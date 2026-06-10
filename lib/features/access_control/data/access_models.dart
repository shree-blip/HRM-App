import '../../../core/permissions/permission.dart';

/// Roles, in the order React lists them (also the matrix column order).
const List<String> kAccessRoles = ['vp', 'admin', 'line_manager', 'supervisor', 'employee'];

const Map<String, String> kRoleLabels = {
  'vp': 'Executive',
  'admin': 'Admin',
  'supervisor': 'Supervisor',
  'line_manager': 'Line Manager',
  'employee': 'Employee',
};

String roleLabel(String role) => kRoleLabels[role] ?? role;

/// Permission categories grouped by module — mirrors React PERMISSION_CATEGORIES.
const Map<String, List<Permission>> kPermissionCategories = {
  'Access Control': [Permission.manageAccess],
  'Team / Employees': [
    Permission.manageEmployees,
    Permission.viewEmployeesAll,
    Permission.viewEmployeesReportsOnly,
    Permission.manageSalariesAll,
  ],
  'Attendance': [
    Permission.viewAttendanceAll,
    Permission.viewAttendanceReportsOnly,
    Permission.viewOwnAttendance,
    Permission.editAttendance,
  ],
  'Leave & Approvals': [Permission.viewLeave, Permission.approveLeave],
  'Announcements': [
    Permission.addAnnouncement,
    Permission.editAnnouncement,
    Permission.deleteAnnouncement,
    Permission.viewAnnouncements,
  ],
  'Documents': [Permission.manageDocuments, Permission.viewDocuments],
  'Reports': [Permission.viewReports],
  'Payroll & Payslips': [Permission.managePayroll, Permission.viewPayroll, Permission.viewPayslips],
  'Tasks': [Permission.manageTasks, Permission.viewTasks],
  'Calendar': [Permission.manageCalendar],
  'Onboarding': [Permission.manageOnboarding, Permission.viewOnboarding],
  'Loans': [Permission.manageLoans, Permission.viewLoans],
  'Invoices': [Permission.viewInvoices, Permission.manageInvoices],
  'Support': [
    Permission.manageSupport,
    Permission.viewSupport,
    Permission.viewBugReports,
    Permission.submitBugReports,
    Permission.viewGrievances,
    Permission.submitGrievances,
    Permission.viewAssetRequests,
    Permission.submitAssetRequests,
  ],
  'Log Sheet': [Permission.viewLogSheet],
  'Performance': [Permission.viewPerformance],
};

/// Flattened permission list in category order (React ALL_PERMISSIONS).
final List<Permission> kAllPermissions = [
  for (final list in kPermissionCategories.values) ...list,
];

/// A user row in Access Control (employee joined with profile + role + spam).
class AccessUser {
  AccessUser({
    required this.id,
    required this.userId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.jobTitle,
    this.department,
    required this.hasAccount,
    this.isSpam = false,
    this.avatarPath,
    this.avatarUrl,
  });

  final String id; // employee id (or user_id for non-employee spam rows)
  final String? userId;
  final String email;
  final String firstName;
  final String lastName;
  String role;
  final String? jobTitle;
  final String? department;
  final bool hasAccount;
  final bool isSpam;
  final String? avatarPath;
  String? avatarUrl;

  String get fullName => '$firstName $lastName'.trim();
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();
}

class RolePermissionRow {
  const RolePermissionRow({required this.role, required this.permission, required this.enabled});
  final String role;
  final String permission;
  final bool enabled;
}

class OverrideRow {
  const OverrideRow({required this.userId, required this.permission, required this.enabled});
  final String userId;
  final String permission;
  final bool enabled;
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.targetUserId,
    required this.changedBy,
    required this.permission,
    required this.oldValue,
    required this.newValue,
    required this.changeType,
    required this.createdAt,
  });
  final String id;
  final String targetUserId;
  final String? changedBy;
  final String permission;
  final bool? oldValue;
  final bool newValue;
  final String changeType;
  final DateTime createdAt;

  factory AuditLogEntry.fromMap(Map<String, dynamic> m) => AuditLogEntry(
        id: m['id'].toString(),
        targetUserId: (m['target_user_id'] ?? '') as String,
        changedBy: m['changed_by'] as String?,
        permission: (m['permission'] ?? '') as String,
        oldValue: m['old_value'] as bool?,
        newValue: m['new_value'] == true,
        changeType: (m['change_type'] ?? '') as String,
        createdAt: DateTime.tryParse((m['created_at'] ?? '') as String)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}
