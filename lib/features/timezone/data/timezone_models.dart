/// One employee row in Timezone Management (ported from the web
/// EmployeeTimezoneRow). No schema changes.
class EmployeeTimezoneRow {
  const EmployeeTimezoneRow({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.department,
    this.jobTitle,
    required this.timezone,
    required this.timezoneStatus,
    required this.email,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? department;
  final String? jobTitle;
  final String timezone;
  final String timezoneStatus;
  final String email;

  String get fullName => '$firstName $lastName'.trim();

  factory EmployeeTimezoneRow.fromMap(Map<String, dynamic> m) => EmployeeTimezoneRow(
        id: (m['id'] ?? '') as String,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        department: m['department'] as String?,
        jobTitle: m['job_title'] as String?,
        timezone: (m['timezone'] ?? 'Asia/Kathmandu') as String,
        timezoneStatus: (m['timezone_status'] ?? 'default') as String,
        email: (m['email'] ?? '') as String,
      );
}
