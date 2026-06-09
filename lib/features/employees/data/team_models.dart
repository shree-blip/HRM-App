/// Models for the employee profile/action views (team, managers, milestones,
/// leave) — ported from the web Employees page + EmployeeProfileDialog.
library;

class TeamMember {
  const TeamMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.department,
    this.jobTitle,
    this.status,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? department;
  final String? jobTitle;
  final String? status;

  String get fullName => '$firstName $lastName'.trim();
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();
  String get displayStatus => (status == null || status!.isEmpty) ? 'active' : status!;

  factory TeamMember.fromMap(Map<String, dynamic> m) => TeamMember(
        id: (m['id'] ?? '') as String,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        department: m['department'] as String?,
        jobTitle: m['job_title'] as String?,
        status: m['status'] as String?,
      );
}

/// A manager the employee reports to ("Reports To" / Crown section).
class ManagerRef {
  const ManagerRef({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.jobTitle,
    this.department,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? jobTitle;
  final String? department;

  String get fullName => '$firstName $lastName'.trim();
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();

  factory ManagerRef.fromMap(Map<String, dynamic> m) => ManagerRef(
        id: (m['id'] ?? '') as String,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        jobTitle: m['job_title'] as String?,
        department: m['department'] as String?,
      );
}

/// Birthday / work-anniversary milestones from the linked profile.
class EmployeeMilestones {
  const EmployeeMilestones({this.dob, this.joining});
  final String? dob;
  final String? joining;

  bool get hasAny => (dob != null && dob!.isNotEmpty) || (joining != null && joining!.isNotEmpty);

  /// Years since joining (null if not joined / future / unparseable).
  int? years(DateTime now) {
    if (joining == null || joining!.isEmpty) return null;
    final d = DateTime.tryParse(joining!);
    if (d == null) return null;
    final y = now.year - d.year;
    return y > 0 ? y : null;
  }
}

/// One leave-type balance row for the leave summary.
class LeaveBalance {
  const LeaveBalance({
    required this.leaveType,
    required this.totalDays,
    required this.usedDays,
  });
  final String leaveType;
  final double totalDays;
  final double usedDays;
  double get remainingDays => totalDays - usedDays;
}
