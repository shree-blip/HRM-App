/// Read-only employee record sourced from the RLS-scoped `employee_directory`
/// view (no salary or other sensitive fields).
class EmployeeDirectoryItem {
  EmployeeDirectoryItem({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.department,
    this.jobTitle,
    this.location,
    this.status,
    this.hireDate,
    this.profileId,
    this.managerId,
    this.lineManagerId,
    this.avatarUrl,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? department;
  final String? jobTitle;
  final String? location;
  final String? status;
  final String? hireDate;
  final String? profileId;
  final String? managerId;
  final String? lineManagerId;

  /// Resolved public avatar URL (filled in by the repository), if any.
  String? avatarUrl;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final c = '$f$l'.trim();
    return c.isEmpty
        ? (email.isNotEmpty ? email[0].toUpperCase() : '?')
        : c.toUpperCase();
  }

  /// "active" | "probation" | "inactive" | null → defaults to active.
  String get displayStatus => (status == null || status!.isEmpty) ? 'active' : status!;

  bool get isRegistered => profileId != null && profileId!.isNotEmpty;

  factory EmployeeDirectoryItem.fromMap(Map<String, dynamic> m) =>
      EmployeeDirectoryItem(
        id: (m['id'] ?? '') as String,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        department: m['department'] as String?,
        jobTitle: m['job_title'] as String?,
        location: m['location'] as String?,
        status: m['status'] as String?,
        hireDate: m['hire_date'] as String?,
        profileId: m['profile_id'] as String?,
        managerId: m['manager_id'] as String?,
        lineManagerId: m['line_manager_id'] as String?,
      );
}

/// People a given employee reports to, and the people who report to them.
class EmployeeRelations {
  const EmployeeRelations({required this.managers, required this.team});
  final List<EmployeeDirectoryItem> managers;
  final List<EmployeeDirectoryItem> team;
}
