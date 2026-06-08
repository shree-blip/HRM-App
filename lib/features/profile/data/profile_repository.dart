import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import 'profile_models.dart';

/// Profile data access — reads/updates the `profiles` table (same columns the
/// web Profile page uses) + resolves the avatar signed URL. No schema changes.
class ProfileRepository {
  String get _uid => supabase.auth.currentUser!.id;

  Future<ProfileData> load() async {
    final row = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name, email, phone, location, '
            'job_title, department, status, date_of_birth, joining_date, avatar_url')
        .eq('user_id', _uid)
        .maybeSingle();
    var p = ProfileData.fromMap((row ?? {'user_id': _uid}).cast<String, dynamic>());
    // Resolve a signed avatar URL (private bucket), like Phase 3.
    if (p.avatarPath != null && p.avatarPath!.isNotEmpty) {
      try {
        var path = p.avatarPath!;
        if (path.contains('/avatars/')) path = path.split('/avatars/').last;
        final url = await supabase.storage.from('avatars').createSignedUrl(path, 3600);
        p = p.withAvatarUrl(url);
      } catch (_) {}
    }
    return p;
  }

  /// Updates the editable profile fields (web parity).
  Future<void> update({
    required String firstName,
    required String lastName,
    String? phone,
    String? location,
    String? dateOfBirth,
    String? joiningDate,
  }) async {
    await supabase.from('profiles').update({
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      'location': (location == null || location.trim().isEmpty) ? null : location.trim(),
      'date_of_birth': (dateOfBirth == null || dateOfBirth.isEmpty) ? null : dateOfBirth,
      'joining_date': (joiningDate == null || joiningDate.isEmpty) ? null : joiningDate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', _uid);
  }

  Future<void> removeAvatar(String? path) async {
    if (path != null && path.isNotEmpty) {
      try {
        var p = path;
        if (p.contains('/avatars/')) p = p.split('/avatars/').last;
        await supabase.storage.from('avatars').remove([p]);
      } catch (_) {}
    }
    await supabase.from('profiles').update({
      'avatar_url': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', _uid);
  }

  /// Change the account password (Supabase verifies via the active session).
  Future<void> changePassword(String newPassword) async {
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }
}
