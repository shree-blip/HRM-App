import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/profile.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

/// Why a session was rejected (mirrors the React `auth_rejected` sessionStorage
/// flag), surfaced to the auth screen as a one-time banner/snackbar.
enum AuthRejection { notAllowed, accountDeactivated }

/// Immutable auth state held by [AuthController]. Mirrors the fields exposed
/// by the React `AuthContext`.
class AppAuthState {
  const AppAuthState({
    this.status = AuthStatus.loading,
    this.user,
    this.session,
    this.profile,
    this.role,
    this.isLineManager = false,
    this.canCreateEmployee = false,
    this.rejection,
  });

  final AuthStatus status;
  final User? user;
  final Session? session;
  final Profile? profile;
  final AppRole? role;
  final bool isLineManager;
  final bool canCreateEmployee;
  final AuthRejection? rejection;

  bool get isManager => role.isManager;
  bool get isAdmin => role.isAdmin;
  bool get isVp => role.isVp;
  bool get isSupervisor => role.isSupervisor;

  const AppAuthState.loading() : this(status: AuthStatus.loading);

  const AppAuthState.unauthenticated({AuthRejection? rejection})
      : this(status: AuthStatus.unauthenticated, rejection: rejection);

  AppAuthState copyWith({
    AuthStatus? status,
    User? user,
    Session? session,
    Profile? profile,
    AppRole? role,
    bool? isLineManager,
    bool? canCreateEmployee,
    AuthRejection? rejection,
    bool clearRejection = false,
    bool clearUser = false,
  }) {
    return AppAuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      session: clearUser ? null : (session ?? this.session),
      profile: clearUser ? null : (profile ?? this.profile),
      role: clearUser ? null : (role ?? this.role),
      isLineManager: clearUser ? false : (isLineManager ?? this.isLineManager),
      canCreateEmployee:
          clearUser ? false : (canCreateEmployee ?? this.canCreateEmployee),
      rejection: clearRejection ? null : (rejection ?? this.rejection),
    );
  }
}
