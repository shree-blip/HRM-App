/// Maps the columns selected by the React `fetchProfile` query from the
/// `profiles` table.
class Profile {
  const Profile({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.department,
    this.jobTitle,
    this.location,
    this.status,
    this.dateOfBirth,
    this.joiningDate,
  });

  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? department;
  final String? jobTitle;
  final String? location;
  final String? status;
  final String? dateOfBirth;
  final String? joiningDate;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final combined = '$f$l'.trim();
    return combined.isEmpty
        ? (email.isNotEmpty ? email[0].toUpperCase() : '?')
        : combined.toUpperCase();
  }

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: (map['id'] ?? '') as String,
        userId: map['user_id'] as String,
        firstName: (map['first_name'] ?? '') as String,
        lastName: (map['last_name'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        phone: map['phone'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        department: map['department'] as String?,
        jobTitle: map['job_title'] as String?,
        location: map['location'] as String?,
        status: map['status'] as String?,
        dateOfBirth: map['date_of_birth'] as String?,
        joiningDate: map['joining_date'] as String?,
      );

  /// Fallback profile built from the auth session when the `profiles` row
  /// can't be read (mirrors the React fallback path).
  factory Profile.fromSession({
    required String userId,
    required String? email,
    String? firstName,
    String? lastName,
  }) =>
      Profile(
        id: '',
        userId: userId,
        firstName: firstName ?? (email?.split('@').first ?? 'User'),
        lastName: lastName ?? '',
        email: email ?? '',
      );
}
