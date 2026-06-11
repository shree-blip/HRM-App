import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../supabase/supabase_client.dart';

/// Visibility scope for team views — ported from the web `teamResolver.ts` +
/// the scoping pattern in useTeamAttendance / useWorkLogs / useLineManagerAccess:
/// VP/Admin are org-wide; every other manager type (line manager, supervisor,
/// legacy manager) is limited to their subordinate tree; everyone else has an
/// empty team scope.
class TeamScope {
  const TeamScope({
    required this.orgWide,
    this.employeeIds = const [],
    this.userIds = const [],
  });

  /// True for VP/Admin — no filtering, queries stay org-wide.
  final bool orgWide;

  /// Subordinate employee ids (direct + indirect), per
  /// `get_all_subordinate_employee_ids`.
  final List<String> employeeIds;

  /// The auth user ids behind those employees (for user_id-keyed tables like
  /// attendance_logs / work_logs / leave_requests).
  final List<String> userIds;

  bool get isEmpty => !orgWide && userIds.isEmpty && employeeIds.isEmpty;
}

/// Resolves the manager's subordinate employee ids + user ids exactly like
/// the web `resolveTeamMemberUserIds` (RPC tree + profile/email resolution).
Future<TeamScope> _resolve(String userId) async {
  // 1. Manager's own employee id.
  final managerEmployeeId =
      await supabase.rpc('get_employee_id_for_user', params: {'_user_id': userId});
  if (managerEmployeeId == null) return const TeamScope(orgWide: false);

  // 2. All subordinate employee ids (direct + indirect).
  final subRes = await supabase.rpc(
    'get_all_subordinate_employee_ids',
    params: {'_manager_employee_id': managerEmployeeId},
  );
  final employeeIds =
      (subRes as List? ?? const []).whereType<String>().toList();
  if (employeeIds.isEmpty) return const TeamScope(orgWide: false);

  // 3. employee ids → profile ids (+ email fallback) → user ids.
  final emps = await supabase
      .from('employees')
      .select('id, profile_id, email')
      .inFilter('id', employeeIds);
  final profileIds = <String>[];
  final fallbackEmails = <String>[];
  for (final r in emps as List) {
    final m = r as Map;
    final pid = m['profile_id'] as String?;
    if (pid != null) {
      profileIds.add(pid);
    } else if ((m['email'] as String?)?.isNotEmpty == true) {
      fallbackEmails.add(m['email'] as String);
    }
  }

  final userIds = <String>{};
  if (profileIds.isNotEmpty) {
    final profs =
        await supabase.from('profiles').select('user_id').inFilter('id', profileIds);
    for (final p in profs as List) {
      final uid = (p as Map)['user_id'] as String?;
      if (uid != null) userIds.add(uid);
    }
  }
  if (fallbackEmails.isNotEmpty) {
    final profs = await supabase
        .from('profiles')
        .select('user_id')
        .inFilter('email', fallbackEmails);
    for (final p in profs as List) {
      final uid = (p as Map)['user_id'] as String?;
      if (uid != null) userIds.add(uid);
    }
  }

  return TeamScope(
    orgWide: false,
    employeeIds: employeeIds,
    userIds: userIds.toList(),
  );
}

/// The current user's team scope. Re-resolves when the user or their role
/// flags change. Read-only (RPCs + selects).
final teamScopeProvider = FutureProvider<TeamScope>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final user = auth.user;
  if (user == null) return const TeamScope(orgWide: false);
  if (auth.isVp || auth.isAdmin) return const TeamScope(orgWide: true);
  final isTeamManager = auth.isLineManager || auth.isSupervisor || auth.isManager;
  if (!isTeamManager) return const TeamScope(orgWide: false);
  try {
    return await _resolve(user.id);
  } catch (_) {
    // Resolution failure must not widen visibility: empty scope.
    return const TeamScope(orgWide: false);
  }
});
