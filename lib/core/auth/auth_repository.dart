import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../supabase/supabase_client.dart';

/// Result of the `verify_signup_email` RPC.
class SignupCheck {
  const SignupCheck({required this.allowed, this.reason, this.employeeId});
  final bool allowed;
  final String? reason; // e.g. "already_used"
  final String? employeeId;
}

/// Result of the `check_employee_active` RPC.
class ActiveCheck {
  const ActiveCheck({required this.active, this.reason, this.name});
  final bool active;
  final String? reason; // e.g. "deactivated"
  final String? name;
}

/// Thin data-access wrapper over Supabase auth + the auth-related RPCs the
/// React app calls. Keeps all backend wiring in one place; the Riverpod
/// controller owns the state machine.
class AuthRepository {
  AuthRepository();

  GoTrueClient get _auth => supabase.auth;

  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  String _normalize(String email) => email.trim().toLowerCase();

  // ── Auth actions ────────────────────────────────────────

  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: _normalize(email), password: password);

  Future<void> signUp(
    String email,
    String password,
    String firstName,
    String lastName,
  ) =>
      _auth.signUp(
        email: _normalize(email),
        password: password,
        data: {'first_name': firstName, 'last_name': lastName},
      );

  Future<void> signOut() => _auth.signOut();

  Future<void> resetPassword(String email) =>
      _auth.resetPasswordForEmail(_normalize(email));

  // ── RPCs (allowlist / deactivation / signup bookkeeping) ─

  /// `verify_signup_email` — allowlist gate used on signup.
  Future<SignupCheck> verifySignupEmail(String email) async {
    final data = await supabase
        .rpc('verify_signup_email', params: {'check_email': _normalize(email)});
    final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
    return SignupCheck(
      allowed: map['allowed'] == true,
      reason: map['reason'] as String?,
      employeeId: map['employee_id'] as String?,
    );
  }

  /// `check_employee_active` — blocks deactivated employees from logging in.
  Future<ActiveCheck> checkEmployeeActive(String email) async {
    final data = await supabase.rpc(
      'check_employee_active',
      params: {'check_email': _normalize(email)},
    );
    final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
    return ActiveCheck(
      active: map['active'] == true,
      reason: map['reason'] as String?,
      name: map['name'] as String?,
    );
  }

  /// Marks an allowlisted email as consumed after a successful signup.
  Future<void> markSignupUsed(String email) async {
    await supabase
        .rpc('mark_signup_used', params: {'check_email': _normalize(email)});
  }

  /// Pre-fills first/last name from the employee directory (readonly fields
  /// in the React signup form).
  Future<({String firstName, String lastName})?> employeeName(
    String employeeId,
  ) async {
    final row = await supabase
        .from('employee_directory')
        .select('first_name, last_name')
        .eq('id', employeeId)
        .maybeSingle();
    if (row == null) return null;
    return (
      firstName: (row['first_name'] ?? '') as String,
      lastName: (row['last_name'] ?? '') as String,
    );
  }

  // ── Profile / role / manager status ─────────────────────

  Future<Profile?> fetchProfile(String userId) async {
    try {
      final row = await supabase
          .from('profiles')
          .select(
            'id, user_id, first_name, last_name, email, phone, avatar_url, '
            'department, job_title, location, status, date_of_birth, joining_date',
          )
          .eq('user_id', userId)
          .maybeSingle();
      if (row != null) return Profile.fromMap(row);
    } catch (_) {
      // fall through to session fallback below
    }
    final sessionUser = currentUser;
    if (sessionUser != null && sessionUser.id == userId) {
      final meta = sessionUser.userMetadata ?? const {};
      return Profile.fromSession(
        userId: userId,
        email: sessionUser.email,
        firstName: meta['first_name'] as String?,
        lastName: meta['last_name'] as String?,
      );
    }
    return null;
  }

  /// All role strings for a user (a user may hold several).
  Future<List<String>> fetchRoles(String userId) async {
    final rows =
        await supabase.from('user_roles').select('role').eq('user_id', userId);
    return (rows as List)
        .map((r) => (r as Map)['role'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<bool> isLineManager(String userId) async {
    final data =
        await supabase.rpc('is_line_manager', params: {'_user_id': userId});
    return data == true;
  }

  Future<bool> canCreateEmployee(String userId) async {
    final data =
        await supabase.rpc('can_create_employee', params: {'_user_id': userId});
    return data == true;
  }
}
