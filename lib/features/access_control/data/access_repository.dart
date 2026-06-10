import '../../../core/supabase/supabase_client.dart';
import 'access_models.dart';

/// Access Control data access — mirrors the web AccessControl page logic.
/// No schema changes; uses existing tables/RPCs.
class AccessRepository {
  /// Active employees joined with profile (avatar/user_id), role, and spam
  /// flag; plus non-employee spam profiles — exactly like the web fetchUsers.
  Future<List<AccessUser>> fetchUsers() async {
    final employees = await supabase
        .from('employees')
        .select('id, email, first_name, last_name, job_title, department, profile_id, status')
        .eq('status', 'active')
        .order('first_name');

    final profiles = await supabase.from('profiles').select('id, user_id, email, first_name, last_name, avatar_url');
    final roles = await supabase.from('user_roles').select('user_id, role');
    final spam = await supabase.from('spam_users').select('user_id, email');

    final spamUserIds = <String>{};
    final spamEmails = <String>{};
    for (final s in spam as List) {
      final m = s as Map;
      if (m['user_id'] != null) spamUserIds.add(m['user_id'] as String);
      if (m['email'] != null) spamEmails.add((m['email'] as String).toLowerCase());
    }

    final profileById = <String, Map>{};
    final profileByUserId = <String, Map>{};
    for (final p in profiles as List) {
      final m = p as Map;
      profileById[m['id'] as String] = m;
      if (m['user_id'] != null) profileByUserId[m['user_id'] as String] = m;
    }
    final roleByUser = <String, String>{};
    for (final r in roles as List) {
      final m = r as Map;
      if (m['user_id'] != null) roleByUser[m['user_id'] as String] = m['role'] as String;
    }

    final employeeUserIds = <String>{};
    for (final e in employees as List) {
      final m = e as Map;
      final prof = m['profile_id'] != null ? profileById[m['profile_id']] : null;
      if (prof?['user_id'] != null) employeeUserIds.add(prof!['user_id'] as String);
    }

    final out = <AccessUser>[];
    for (final e in employees) {
      final m = e as Map;
      final prof = m['profile_id'] != null ? profileById[m['profile_id']] : null;
      final userId = prof?['user_id'] as String?;
      final email = (m['email'] ?? '') as String;
      final isSpam = userId != null ? spamUserIds.contains(userId) : spamEmails.contains(email.toLowerCase());
      out.add(AccessUser(
        id: m['id'] as String,
        userId: userId,
        email: email,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        jobTitle: m['job_title'] as String?,
        department: m['department'] as String?,
        role: userId != null ? (roleByUser[userId] ?? 'employee') : 'employee',
        hasAccount: userId != null,
        isSpam: isSpam,
        avatarPath: prof?['avatar_url'] as String?,
      ),);
    }

    // Non-employee spam profiles.
    for (final s in spam) {
      final m = s as Map;
      final uid = m['user_id'] as String?;
      if (uid == null || employeeUserIds.contains(uid)) continue;
      final prof = profileByUserId[uid];
      if (prof == null) continue;
      out.add(AccessUser(
        id: uid,
        userId: uid,
        email: (m['email'] ?? '') as String,
        firstName: (prof['first_name'] ?? 'Spam') as String,
        lastName: (prof['last_name'] ?? 'User') as String,
        jobTitle: 'UNAUTHORIZED',
        department: null,
        role: roleByUser[uid] ?? 'employee',
        hasAccount: true,
        isSpam: true,
        avatarPath: prof['avatar_url'] as String?,
      ),);
    }

    await _attachAvatars(out);
    return out;
  }

  Future<void> _attachAvatars(List<AccessUser> users) async {
    final paths = users
        .map((u) => u.avatarPath)
        .whereType<String>()
        .where((p) => p.isNotEmpty && !p.startsWith('http'))
        .toSet()
        .toList();
    final signed = <String, String>{};
    if (paths.isNotEmpty) {
      try {
        final results = await supabase.storage.from('avatars').createSignedUrls(paths, 3600);
        for (final r in results) {
          if (r.signedUrl.isNotEmpty) signed[r.path] = r.signedUrl;
        }
      } catch (_) {}
    }
    for (final u in users) {
      final p = u.avatarPath;
      if (p == null || p.isEmpty) continue;
      u.avatarUrl = p.startsWith('http') ? p : signed[p];
    }
  }

  Future<List<RolePermissionRow>> fetchRolePermissions() async {
    final rows = await supabase.from('role_permissions').select('role, permission, enabled');
    return (rows as List).map((r) {
      final m = r as Map;
      return RolePermissionRow(
        role: m['role'] as String,
        permission: m['permission'] as String,
        enabled: m['enabled'] == true,
      );
    }).toList();
  }

  Future<List<OverrideRow>> fetchOverrides() async {
    final rows = await supabase.from('user_permission_overrides').select('user_id, permission, enabled');
    return (rows as List).map((r) {
      final m = r as Map;
      return OverrideRow(
        userId: m['user_id'] as String,
        permission: m['permission'] as String,
        enabled: m['enabled'] == true,
      );
    }).toList();
  }

  Future<bool> isSecurityMonitor(String userId) async {
    try {
      final res = await supabase.rpc('is_security_monitor', params: {'_user_id': userId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Atomic role change via the backend RPC (avoids duplicate-key errors).
  Future<void> changeUserRole(String targetUserId, String newRole) async {
    await supabase.rpc('change_user_role', params: {
      '_target_user_id': targetUserId,
      '_new_role': newRole,
    },);
  }

  /// Direct update of a role_permissions row (rows pre-exist), like the web.
  Future<void> updateRolePermission(String role, String permission, bool enabled) async {
    await supabase
        .from('role_permissions')
        .update({'enabled': enabled})
        .eq('role', role)
        .eq('permission', permission);
  }

  /// Three-state override cycle (null → flip role default → OFF → remove),
  /// each writing a permission_audit_logs entry — mirrors the web exactly.
  Future<void> cycleUserOverride({
    required String targetUserId,
    required String permission,
    required bool? currentOverride,
    required bool roleDefault,
    required String changedBy,
  }) async {
    if (currentOverride == null) {
      final newValue = !roleDefault;
      await supabase.from('user_permission_overrides').insert({
        'user_id': targetUserId,
        'permission': permission,
        'enabled': newValue,
      });
      await _audit(targetUserId, changedBy, permission, null, newValue, 'override_created');
    } else if (currentOverride == true) {
      await supabase
          .from('user_permission_overrides')
          .update({'enabled': false})
          .eq('user_id', targetUserId)
          .eq('permission', permission);
      await _audit(targetUserId, changedBy, permission, true, false, 'override_updated');
    } else {
      await supabase
          .from('user_permission_overrides')
          .delete()
          .eq('user_id', targetUserId)
          .eq('permission', permission);
      await _audit(targetUserId, changedBy, permission, false, roleDefault, 'override_removed');
    }
  }

  Future<void> _audit(String targetUserId, String changedBy, String permission, bool? oldValue, bool newValue, String changeType) async {
    try {
      await supabase.from('permission_audit_logs').insert({
        'target_user_id': targetUserId,
        'changed_by': changedBy,
        'permission': permission,
        'old_value': oldValue,
        'new_value': newValue,
        'change_type': changeType,
      });
    } catch (_) {}
  }

  Future<List<AuditLogEntry>> fetchAuditLogs(String targetUserId) async {
    try {
      final rows = await supabase
          .from('permission_audit_logs')
          .select('*')
          .eq('target_user_id', targetUserId)
          .order('created_at', ascending: false)
          .limit(50);
      return (rows as List).map((r) => AuditLogEntry.fromMap((r as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }
}
