import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// Notification preferences (user_preferences table).
class UserPreferences {
  const UserPreferences({
    this.leave = true,
    this.task = true,
    this.payroll = true,
    this.performance = false,
    this.emailDigest = false,
  });
  final bool leave;
  final bool task;
  final bool payroll;
  final bool performance;
  final bool emailDigest;

  factory UserPreferences.fromMap(Map<String, dynamic>? m) => UserPreferences(
        leave: m?['leave_notifications'] ?? true,
        task: m?['task_notifications'] ?? true,
        payroll: m?['payroll_notifications'] ?? true,
        performance: m?['performance_notifications'] ?? false,
        emailDigest: m?['email_digest'] ?? false,
      );
}

/// Settings data access — profile basic fields, notification preferences,
/// password, avatar upload/remove. Mirrors the web useSettings + Settings page.
/// No schema changes.
class SettingsRepository {
  String get _uid => supabase.auth.currentUser!.id;

  Future<UserPreferences> loadPreferences() async {
    final row = await supabase.from('user_preferences').select().eq('user_id', _uid).maybeSingle();
    return UserPreferences.fromMap(row?.cast<String, dynamic>());
  }

  /// Update one preference key; inserts a row if none exists yet.
  Future<void> updatePreference(String key, bool value) async {
    final updated = await supabase
        .from('user_preferences')
        .update({key: value, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', _uid)
        .select('id');
    if ((updated as List).isEmpty) {
      await supabase.from('user_preferences').insert({'user_id': _uid, key: value});
    }
  }

  Future<void> updateProfile({required String firstName, required String lastName, String? phone}) async {
    await supabase.from('profiles').update({
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', _uid);
  }

  /// Re-authenticates with the current password (web parity: prevents changing
  /// the password without proving the current one), then updates it.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final email = supabase.auth.currentUser?.email;
    if (email == null) {
      throw const AuthException('No authenticated user.');
    }
    // Verify the current password by re-authenticating.
    await supabase.auth.signInWithPassword(email: email, password: currentPassword);
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Upload a profile photo to the `avatars` bucket (web parity: deletes old,
  /// path `<uid>/avatar-<ts>.<ext>`, stores the path in profiles.avatar_url).
  Future<void> uploadAvatar(Uint8List bytes, String ext) async {
    // Remove old avatar if present.
    final prof = await supabase.from('profiles').select('avatar_url').eq('user_id', _uid).maybeSingle();
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
        final p = path.contains('/avatars/') ? path.split('/avatars/').last : path;
        await supabase.storage.from('avatars').remove([p]);
      } catch (_) {}
    }
    await supabase.from('profiles').update({
      'avatar_url': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', _uid);
  }
}
