import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../supabase/supabase_client.dart';
import 'permission.dart';

/// Effective permissions for the current user, with loading flag.
class PermissionsState {
  const PermissionsState({this.permissions = const {}, this.loading = true});

  final Map<Permission, bool> permissions;
  final bool loading;

  bool has(Permission p) => permissions[p] ?? false;

  /// At least one of [perms] is granted (matches React `hasRouteAccess`).
  bool hasAny(List<Permission> perms) => perms.any(has);

  bool hasRouteAccess(String route) {
    final required = kRoutePermissions[route];
    if (required == null) return true; // unmapped routes are open
    return hasAny(required);
  }

  PermissionsState copyWith({
    Map<Permission, bool>? permissions,
    bool? loading,
  }) =>
      PermissionsState(
        permissions: permissions ?? this.permissions,
        loading: loading ?? this.loading,
      );
}

final permissionsControllerProvider =
    NotifierProvider<PermissionsController, PermissionsState>(
  PermissionsController.new,
);

/// Computes effective permissions exactly like the React `usePermissions`:
///   1. start from `role_permissions` for the user's role
///   2. apply per-user `user_permission_overrides` on top
/// Re-fetches on realtime changes to either table.
class PermissionsController extends Notifier<PermissionsState> {
  final List<RealtimeChannel> _channels = [];

  @override
  PermissionsState build() {
    // Rebuild whenever the user or role changes.
    final auth = ref.watch(authControllerProvider);

    ref.onDispose(_teardownChannels);

    if (auth.status != AuthStatus.authenticated ||
        auth.user == null ||
        auth.role == null) {
      _teardownChannels();
      return const PermissionsState(permissions: {}, loading: false);
    }

    // Kick off async fetch + realtime subscriptions.
    Future.microtask(() => _load(auth));
    return const PermissionsState(loading: true);
  }

  Future<void> _load(AppAuthState auth) async {
    final userId = auth.user!.id;
    final roleValue = auth.role!.dbValue;

    final results = await Future.wait([
      supabase
          .from('role_permissions')
          .select('permission, enabled')
          .eq('role', roleValue),
      supabase
          .from('user_permission_overrides')
          .select('permission, enabled')
          .eq('user_id', userId),
    ]);

    final rolePerms = <String, bool>{};
    for (final row in results[0] as List) {
      final m = row as Map;
      rolePerms[m['permission'] as String] = m['enabled'] == true;
    }

    final overrides = <String, bool>{};
    for (final row in results[1] as List) {
      final m = row as Map;
      overrides[m['permission'] as String] = m['enabled'] == true;
    }

    final effective = <Permission, bool>{};
    for (final p in Permission.values) {
      effective[p] = overrides[p.key] ?? rolePerms[p.key] ?? false;
    }

    state = PermissionsState(permissions: effective, loading: false);

    _subscribeRealtime(userId);
  }

  void _subscribeRealtime(String userId) {
    if (_channels.isNotEmpty) return;

    final overridesChannel = supabase
        .channel('my-overrides')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_permission_overrides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _refetch(),
        )
        .subscribe();

    final rolePermChannel = supabase
        .channel('role-perms-change')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'role_permissions',
          callback: (_) => _refetch(),
        )
        .subscribe();

    _channels.addAll([overridesChannel, rolePermChannel]);
  }

  Future<void> _refetch() async {
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated && auth.role != null) {
      await _load(auth);
    }
  }

  void _teardownChannels() {
    for (final c in _channels) {
      supabase.removeChannel(c);
    }
    _channels.clear();
  }
}
