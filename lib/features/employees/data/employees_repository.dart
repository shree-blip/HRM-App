import '../../../core/supabase/supabase_client.dart';
import 'employee.dart';

/// Read-only employee data access. Everything is scoped by Supabase RLS via
/// the `employee_directory` view — VP/Admin see everyone, line managers see
/// their reports. No schema changes; no writes.
class EmployeesRepository {
  /// All employees visible to the current user, ordered by first name, with
  /// avatar URLs resolved from the public `avatars` bucket.
  Future<List<EmployeeDirectoryItem>> list() async {
    final rows = await supabase
        .from('employee_directory')
        .select(
          'id, first_name, last_name, email, department, job_title, '
          'location, status, hire_date, profile_id, manager_id, line_manager_id',
        )
        .order('first_name', ascending: true);

    final items = (rows as List)
        .map((r) => EmployeeDirectoryItem.fromMap((r as Map).cast<String, dynamic>()))
        .where((e) => e.id.isNotEmpty)
        .toList();

    await _attachAvatars(items);
    return items;
  }

  Future<EmployeeDirectoryItem?> byId(String id) async {
    final row = await supabase
        .from('employee_directory')
        .select(
          'id, first_name, last_name, email, department, job_title, '
          'location, status, hire_date, profile_id, manager_id, line_manager_id',
        )
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final item = EmployeeDirectoryItem.fromMap(row);
    await _attachAvatars([item]);
    return item;
  }

  /// Resolves who an employee reports to (managers) and who reports to them
  /// (team) — combining the team_members junction with legacy
  /// line_manager_id / manager_id columns, all via the directory view.
  Future<EmployeeRelations> relations(String employeeId) async {
    final managers = await _managersOf(employeeId);
    final team = await _teamOf(employeeId);
    return EmployeeRelations(managers: managers, team: team);
  }

  Future<List<EmployeeDirectoryItem>> _managersOf(String employeeId) async {
    final tm = await supabase
        .from('team_members')
        .select('manager_employee_id')
        .eq('member_employee_id', employeeId);
    final ids = (tm as List)
        .map((r) => (r as Map)['manager_employee_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return [];
    return _directoryByIds(ids);
  }

  Future<List<EmployeeDirectoryItem>> _teamOf(String managerId) async {
    final junction = await supabase
        .from('team_members')
        .select('member_employee_id')
        .eq('manager_employee_id', managerId);
    final ids = (junction as List)
        .map((r) => (r as Map)['member_employee_id'] as String?)
        .whereType<String>()
        .toSet();

    // Legacy direct-report columns from the directory view.
    final legacy = await supabase
        .from('employee_directory')
        .select(
          'id, first_name, last_name, email, department, job_title, '
          'location, status, profile_id',
        )
        .or('line_manager_id.eq.$managerId,manager_id.eq.$managerId');

    final byId = <String, EmployeeDirectoryItem>{};
    for (final r in legacy as List) {
      final e = EmployeeDirectoryItem.fromMap((r as Map).cast<String, dynamic>());
      if (e.id.isNotEmpty) byId[e.id] = e;
    }
    final missing = ids.where((id) => !byId.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      for (final e in await _directoryByIds(missing)) {
        byId[e.id] = e;
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
    await _attachAvatars(list);
    return list;
  }

  Future<List<EmployeeDirectoryItem>> _directoryByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await supabase
        .from('employee_directory')
        .select(
          'id, first_name, last_name, email, department, job_title, '
          'location, status, profile_id',
        )
        .inFilter('id', ids)
        .order('first_name', ascending: true);
    final items = (rows as List)
        .map((r) => EmployeeDirectoryItem.fromMap((r as Map).cast<String, dynamic>()))
        .where((e) => e.id.isNotEmpty)
        .toList();
    await _attachAvatars(items);
    return items;
  }

  /// Maps profile_id → avatar_url path and resolves a signed URL for each
  /// item. The `avatars` bucket is private, so we sign (matches the web app's
  /// useAvatarUrl). Avatars are non-critical: any failure falls back to initials.
  Future<void> _attachAvatars(List<EmployeeDirectoryItem> items) async {
    final profileIds = items
        .map((e) => e.profileId)
        .whereType<String>()
        .toSet()
        .toList();
    if (profileIds.isEmpty) return;
    try {
      final rows = await supabase
          .from('profiles')
          .select('id, avatar_url')
          .inFilter('id', profileIds);
      final pathByProfile = <String, String>{};
      for (final r in rows as List) {
        final m = r as Map;
        final path = m['avatar_url'] as String?;
        if (path != null && path.isNotEmpty) {
          pathByProfile[m['id'] as String] = path;
        }
      }

      // Already-absolute URLs are used directly; relative paths get signed.
      final toSign = pathByProfile.values
          .where((p) => !p.startsWith('http'))
          .toSet()
          .toList();
      final signed = <String, String>{};
      if (toSign.isNotEmpty) {
        final results =
            await supabase.storage.from('avatars').createSignedUrls(toSign, 3600);
        for (final r in results) {
          final p = r.path;
          if (r.signedUrl.isNotEmpty) signed[p] = r.signedUrl;
        }
      }

      for (final e in items) {
        final path = e.profileId != null ? pathByProfile[e.profileId] : null;
        if (path == null) continue;
        e.avatarUrl = path.startsWith('http') ? path : signed[path];
      }
    } catch (_) {
      // Avatars are non-critical; fall back to initials.
    }
  }
}
