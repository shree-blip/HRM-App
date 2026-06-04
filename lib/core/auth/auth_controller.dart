import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());

final authControllerProvider =
    NotifierProvider<AuthController, AppAuthState>(AuthController.new);

/// Thrown by [AuthController.signIn] when the account is deactivated, so the
/// UI can show a friendly message without ever creating a session
/// (mirrors the React pre-login `check_employee_active` call).
class AccountDeactivatedException implements Exception {
  const AccountDeactivatedException();
}

/// Owns the auth state machine. Faithfully ports the listener behaviour in
/// the React `AuthContext`:
///  - SIGNED_IN  -> deactivation check, then allowlist check, then load data
///  - TOKEN_REFRESHED / INITIAL_SESSION -> skip allowlist, just refresh data
///  - SIGNED_OUT -> clear everything
class AuthController extends Notifier<AppAuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  StreamSubscription<AuthState>? _sub;

  // Once validated in this app session, don't re-run the allowlist RPC on
  // every token refresh (the React fix that stopped random logouts).
  bool _allowlistValidated = false;
  bool _initInFlight = false;

  @override
  AppAuthState build() {
    _sub = _repo.onAuthStateChange.listen(_onAuthEvent);
    ref.onDispose(() => _sub?.cancel());
    // The SDK emits `initialSession` right away, which resolves this.
    return const AppAuthState.loading();
  }

  Future<void> _onAuthEvent(AuthState data) async {
    final event = data.event;
    final session = data.session;
    final user = session?.user;

    if (user == null) {
      _allowlistValidated = false;
      state = AppAuthState.unauthenticated(rejection: state.rejection);
      return;
    }

    switch (event) {
      case AuthChangeEvent.tokenRefreshed:
        // Keep session fresh; do NOT re-check the allowlist.
        state = state.copyWith(session: session, user: user);
        await _loadUserData(user, session);
        break;
      case AuthChangeEvent.initialSession:
        // Restored session — already validated previously, skip allowlist.
        _allowlistValidated = true;
        await _loadUserData(user, session);
        break;
      case AuthChangeEvent.signedIn:
        await _handleSignedIn(user, session);
        break;
      default:
        // userUpdated / passwordRecovery / mfa — just keep data fresh.
        if (state.status == AuthStatus.authenticated) {
          await _loadUserData(user, session);
        }
        break;
    }
  }

  Future<void> _handleSignedIn(User user, Session? session) async {
    final email = user.email;
    if (email == null) {
      await _loadUserData(user, session);
      return;
    }

    // 1) Deactivation guard.
    try {
      final active = await _repo.checkEmployeeActive(email);
      if (!active.active && active.reason == 'deactivated') {
        await _rejectAndSignOut(AuthRejection.accountDeactivated);
        return;
      }
    } catch (_) {
      // Don't block login on RPC failure.
    }

    // 2) Allowlist guard — skip if already validated this app session.
    if (!_allowlistValidated) {
      try {
        final check = await _repo.verifySignupEmail(email);
        final allowed = check.allowed || check.reason == 'already_used';
        if (!allowed) {
          await _rejectAndSignOut(AuthRejection.notAllowed);
          return;
        }
      } catch (_) {
        // Network blip — don't sign out an otherwise valid session.
      }
    }

    _allowlistValidated = true;
    await _loadUserData(user, session);
  }

  Future<void> _rejectAndSignOut(AuthRejection reason) async {
    await _repo.signOut();
    _allowlistValidated = false;
    state = AppAuthState.unauthenticated(rejection: reason);
  }

  Future<void> _loadUserData(User user, Session? session) async {
    if (_initInFlight) return;
    _initInFlight = true;
    try {
      final results = await Future.wait([
        _repo.fetchProfile(user.id),
        _repo.fetchRoles(user.id),
        _repo.isLineManager(user.id),
        _repo.canCreateEmployee(user.id),
      ]);

      final profile = results[0] as dynamic;
      final roles = results[1] as List<String>;
      final isLineManager = results[2] as bool;
      final canCreate = results[3] as bool;

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        session: session,
        profile: profile,
        role: AppRole.highest(roles),
        isLineManager: isLineManager,
        canCreateEmployee: canCreate,
      );
    } finally {
      _initInFlight = false;
    }
  }

  // ── Public actions used by the UI ───────────────────────

  /// Pre-checks deactivation (so we never create a session for a deactivated
  /// account), then signs in. Throws [AccountDeactivatedException] or
  /// [AuthException] on failure.
  Future<void> signIn(String email, String password) async {
    try {
      final active = await _repo.checkEmployeeActive(email);
      if (!active.active && active.reason == 'deactivated') {
        throw const AccountDeactivatedException();
      }
    } on AccountDeactivatedException {
      rethrow;
    } catch (_) {
      // Ignore RPC failures; proceed to normal sign-in.
    }
    await _repo.signIn(email, password);
  }

  /// Signs up an allowlisted user, then marks the invite consumed.
  Future<void> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    await _repo.signUp(email, password, firstName, lastName);
    try {
      await _repo.markSignupUsed(email);
    } catch (_) {
      // Non-fatal; the account already exists at this point.
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AppAuthState.unauthenticated();
  }

  Future<void> resetPassword(String email) => _repo.resetPassword(email);

  Future<SignupCheck> verifySignupEmail(String email) =>
      _repo.verifySignupEmail(email);

  Future<({String firstName, String lastName})?> employeeName(String id) =>
      _repo.employeeName(id);

  void clearRejection() {
    if (state.rejection != null) {
      state = state.copyWith(clearRejection: true);
    }
  }
}
