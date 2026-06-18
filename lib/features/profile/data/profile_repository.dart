import 'dart:typed_data';

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
    await _notifyProfileUpdated('${firstName.trim()} ${lastName.trim()}'.trim());
  }

  /// In-app notifications on profile save — exact web Profile.tsx behavior:
  /// confirmation to self + "review if required" copy to direct managers and
  /// all Admin/VP users (excluding self). Best-effort.
  Future<void> _notifyProfileUpdated(String empName) async {
    try {
      await supabase.rpc('create_notification', params: {
        'p_user_id': _uid,
        'p_title': '✅ Profile Updated',
        'p_message': 'Your profile has been updated successfully.',
        'p_type': 'success',
        'p_link': '/profile',
      },);

      final targets = <String>{};
      // Direct managers (team_members -> manager employees -> auth user ids).
      try {
        final empId = await supabase
            .rpc('get_employee_id_for_user', params: {'_user_id': _uid});
        if (empId is String) {
          final tm = await supabase
              .from('team_members')
              .select('manager_employee_id')
              .eq('member_employee_id', empId);
          final mgrEmpIds = (tm as List)
              .map((r) => (r as Map)['manager_employee_id'] as String?)
              .whereType<String>()
              .toList();
          if (mgrEmpIds.isNotEmpty) {
            final emps = await supabase
                .from('employees')
                .select('profile_id')
                .inFilter('id', mgrEmpIds);
            final profileIds = (emps as List)
                .map((r) => (r as Map)['profile_id'] as String?)
                .whereType<String>()
                .toList();
            if (profileIds.isNotEmpty) {
              final profs = await supabase
                  .from('profiles')
                  .select('user_id')
                  .inFilter('id', profileIds);
              for (final p in profs as List) {
                final u = (p as Map)['user_id'] as String?;
                if (u != null) targets.add(u);
              }
            }
          }
        }
      } catch (_) {}
      // Admin/VP users.
      try {
        final roles = await supabase
            .from('user_roles')
            .select('user_id')
            .inFilter('role', ['vp', 'admin']);
        for (final r in roles as List) {
          final u = (r as Map)['user_id'] as String?;
          if (u != null) targets.add(u);
        }
      } catch (_) {}
      targets.remove(_uid);
      for (final t in targets) {
        await supabase.rpc('create_notification', params: {
          'p_user_id': t,
          'p_title': '👤 Employee Profile Updated',
          'p_message':
              '$empName has updated their profile. Please review if required.',
          'p_type': 'info',
          'p_link': '/employees',
        },);
      }
    } catch (_) {
      // Best-effort; the profile save itself already succeeded.
    }
  }

  /// Upload a profile photo to the `avatars` bucket (web parity: deletes old,
  /// path `<uid>/avatar-<ts>.<ext>`, stores the path in profiles.avatar_url).
  Future<void> uploadAvatar(Uint8List bytes, String ext) async {
    final prof = await supabase
        .from('profiles')
        .select('avatar_url')
        .eq('user_id', _uid)
        .maybeSingle();
    final old = prof?['avatar_url'] as String?;
    if (old != null && old.isNotEmpty) {
      try {
        final p = old.contains('/avatars/') ? old.split('/avatars/').last : old;
        await supabase.storage.from('avatars').remove([p]);
      } catch (_) {}
    }
    final path = '$_uid/avatar-${DateTime.now().toUtc().millisecondsSinceEpoch}.$ext';
    await supabase.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    await supabase.from('profiles').update({
      'avatar_url': path,
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
