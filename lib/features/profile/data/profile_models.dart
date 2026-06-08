/// Profile data (all from the `profiles` table, per the web Profile page).
class ProfileData {
  const ProfileData({
    required this.userId,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.location,
    this.jobTitle,
    this.department,
    this.status,
    this.dateOfBirth,
    this.joiningDate,
    this.avatarPath,
    this.avatarUrl,
  });

  final String userId;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? location;
  final String? jobTitle; // read-only (HR-managed)
  final String? department; // read-only
  final String? status; // read-only
  final String? dateOfBirth; // YYYY-MM-DD
  final String? joiningDate; // YYYY-MM-DD
  final String? avatarPath; // storage path in `avatars`
  final String? avatarUrl; // resolved signed URL

  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();
  String get initials {
    final f = (firstName ?? '').trim();
    final l = (lastName ?? '').trim();
    final a = f.isNotEmpty ? f[0] : '';
    final b = l.isNotEmpty ? l[0] : '';
    final s = '$a$b';
    return s.isEmpty ? '?' : s.toUpperCase();
  }

  ProfileData withAvatarUrl(String? url) => ProfileData(
        userId: userId, firstName: firstName, lastName: lastName, email: email,
        phone: phone, location: location, jobTitle: jobTitle, department: department,
        status: status, dateOfBirth: dateOfBirth, joiningDate: joiningDate,
        avatarPath: avatarPath, avatarUrl: url,
      );

  factory ProfileData.fromMap(Map<String, dynamic> m) => ProfileData(
        userId: m['user_id'] as String,
        firstName: m['first_name'] as String?,
        lastName: m['last_name'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        location: m['location'] as String?,
        jobTitle: m['job_title'] as String?,
        department: m['department'] as String?,
        status: m['status'] as String?,
        dateOfBirth: m['date_of_birth'] as String?,
        joiningDate: m['joining_date'] as String?,
        avatarPath: m['avatar_url'] as String?,
      );
}
