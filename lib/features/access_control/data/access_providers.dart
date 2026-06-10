import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import 'access_models.dart';
import 'access_repository.dart';

final accessRepositoryProvider = Provider<AccessRepository>((_) => AccessRepository());

class AccessState {
  const AccessState({
    this.users = const [],
    this.rolePermissions = const [],
    this.overrides = const [],
    this.isSecurityMonitor = false,
    this.loading = true,
  });
  final List<AccessUser> users;
  final List<RolePermissionRow> rolePermissions;
  final List<OverrideRow> overrides;
  final bool isSecurityMonitor;
  final bool loading;

  AccessState copyWith({
    List<AccessUser>? users,
    List<RolePermissionRow>? rolePermissions,
    List<OverrideRow>? overrides,
    bool? isSecurityMonitor,
    bool? loading,
  }) =>
      AccessState(
        users: users ?? this.users,
        rolePermissions: rolePermissions ?? this.rolePermissions,
        overrides: overrides ?? this.overrides,
        isSecurityMonitor: isSecurityMonitor ?? this.isSecurityMonitor,
        loading: loading ?? this.loading,
      );

  bool roleHas(String role, String permissionKey) =>
      rolePermissions.any((rp) => rp.role == role && rp.permission == permissionKey && rp.enabled);

  /// Override state for a user+permission: true/false, or null when none.
  bool? overrideFor(String userId, String permissionKey) {
    for (final o in overrides) {
      if (o.userId == userId && o.permission == permissionKey) return o.enabled;
    }
    return null;
  }

  int overrideCount(String? userId) =>
      userId == null ? 0 : overrides.where((o) => o.userId == userId).length;
}

final accessControllerProvider =
    NotifierProvider<AccessController, AccessState>(AccessController.new);

class AccessController extends Notifier<AccessState> {
  final List<RealtimeChannel> _channels = [];

  AccessRepository get _repo => ref.read(accessRepositoryProvider);

  @override
  AccessState build() {
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_teardown);
    if (uid == null) return const AccessState(loading: false);
    Future.microtask(() => _loadAll(uid));
    return const AccessState(loading: true);
  }

  Future<void> _loadAll(String uid) async {
    try {
      final results = await Future.wait([
        _repo.fetchUsers(),
        _repo.fetchRolePermissions(),
        _repo.fetchOverrides(),
        _repo.isSecurityMonitor(uid),
      ]);
      state = AccessState(
        users: results[0] as List<AccessUser>,
        rolePermissions: results[1] as List<RolePermissionRow>,
        overrides: results[2] as List<OverrideRow>,
        isSecurityMonitor: results[3] as bool,
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
    _subscribe();
  }

  void _subscribe() {
    if (_channels.isNotEmpty) return;
    _channels.add(supabase
        .channel('ac-user-roles')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'user_roles', callback: (_) => reloadUsers())
        .subscribe(),);
    _channels.add(supabase
        .channel('ac-role-perms')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'role_permissions', callback: (_) => reloadRolePerms())
        .subscribe(),);
    _channels.add(supabase
        .channel('ac-overrides')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'user_permission_overrides', callback: (_) => reloadOverrides())
        .subscribe(),);
  }

  Future<void> reloadUsers() async {
    try {
      state = state.copyWith(users: await _repo.fetchUsers());
    } catch (_) {}
  }

  Future<void> reloadRolePerms() async {
    try {
      state = state.copyWith(rolePermissions: await _repo.fetchRolePermissions());
    } catch (_) {}
  }

  Future<void> reloadOverrides() async {
    try {
      state = state.copyWith(overrides: await _repo.fetchOverrides());
    } catch (_) {}
  }

  Future<void> changeRole(AccessUser u, String newRole) async {
    if (u.userId == null) return;
    await _repo.changeUserRole(u.userId!, newRole);
    await reloadUsers();
  }

  Future<bool> toggleRolePermission(String role, String permissionKey, bool currentEnabled) async {
    try {
      await _repo.updateRolePermission(role, permissionKey, !currentEnabled);
      await reloadRolePerms();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cycleOverride(String targetUserId, String permissionKey, bool? current, bool roleDefault) async {
    final changedBy = supabase.auth.currentUser?.id;
    if (changedBy == null) return;
    await _repo.cycleUserOverride(
      targetUserId: targetUserId,
      permission: permissionKey,
      currentOverride: current,
      roleDefault: roleDefault,
      changedBy: changedBy,
    );
    await reloadOverrides();
  }

  void _teardown() {
    for (final c in _channels) {
      supabase.removeChannel(c);
    }
    _channels.clear();
  }
}

/// Per-user audit log (refreshed when overrides change via the key).
final auditLogsProvider = FutureProvider.autoDispose.family<List<AuditLogEntry>, String>(
  (ref, userId) {
    // Re-run when overrides change so the history stays fresh.
    ref.watch(accessControllerProvider.select((s) => s.overrideCount(userId)));
    return ref.read(accessRepositoryProvider).fetchAuditLogs(userId);
  },
);
