import '../../../core/supabase/supabase_client.dart';
import 'employee.dart';

/// Editable fields for one employee (manager view), prefilled from `employees`.
class EmployeeEditData {
  const EmployeeEditData({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone,
    this.department,
    this.jobTitle,
    this.location,
    this.status,
  });
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? department;
  final String? jobTitle;
  final String? location;
  final String? status;

  factory EmployeeEditData.fromMap(Map<String, dynamic> m) => EmployeeEditData(
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        phone: m['phone'] as String?,
        department: m['department'] as String?,
        jobTitle: m['job_title'] as String?,
        location: m['location'] as String?,
        status: m['status'] as String?,
      );
}

/// A line-manager option for the create form.
class ManagerOption {
  const ManagerOption({required this.id, required this.name, this.jobTitle});
  final String id;
  final String name;
  final String? jobTitle;
  String get label => jobTitle != null && jobTitle!.isNotEmpty ? '$name — $jobTitle' : name;
}

/// Employee data access. Reads via the RLS-scoped `employee_directory` view;
/// manager writes go to the `employees` table (+ team_members / allowed_signups
/// sync) exactly like the web. No schema changes.
class EmployeesRepository {
  String get _uid => supabase.auth.currentUser!.id;

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

  // ── Manager writes ──────────────────────────────────────
  /// Active employees for the line-manager dropdown.
  Future<List<ManagerOption>> managers() async {
    final rows = await supabase
        .from('employees')
        .select('id, first_name, last_name, job_title')
        .or('status.eq.active,status.is.null')
        .order('first_name', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map;
      return ManagerOption(
        id: m['id'] as String,
        name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
        jobTitle: m['job_title'] as String?,
      );
    }).toList();
  }

  /// Full editable row from `employees` (managers have RLS access). Includes
  /// phone, which the directory view omits.
  Future<EmployeeEditData?> fullById(String id) async {
    final row = await supabase
        .from('employees')
        .select('first_name, last_name, email, phone, department, job_title, location, status')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : EmployeeEditData.fromMap(row.cast<String, dynamic>());
  }

  Future<bool> emailExists(String email) async {
    final row = await supabase
        .from('employees')
        .select('id')
        .eq('email', email.trim().toLowerCase())
        .maybeSingle();
    return row != null;
  }

  /// Create an employee (+ team_members link if a line manager is set, +
  /// allowed_signups whitelist, + welcome email). Mirrors the web flow.
  Future<void> createEmployee({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    String? department,
    String? jobTitle,
    required String location,
    String? lineManagerId,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final inserted = await supabase
        .from('employees')
        .insert({
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'email': cleanEmail,
          'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
          'department': department,
          'job_title': jobTitle,
          'location': location,
          'status': 'active',
          'hire_date': DateTime.now().toIso8601String().split('T').first,
          if (lineManagerId != null) 'line_manager_id': lineManagerId,
        })
        .select('id')
        .single();
    final id = inserted['id'] as String;

    // Mirror line-manager assignment into team_members (best-effort).
    if (lineManagerId != null) {
      try {
        await supabase.from('team_members').insert({
          'manager_employee_id': lineManagerId,
          'member_employee_id': id,
        });
      } catch (_) {}
    }

    // Whitelist the email so the new hire can sign up.
    try {
      await supabase.from('allowed_signups').upsert({
        'email': cleanEmail,
        'employee_id': id,
        'invited_by': _uid,
        'invited_at': DateTime.now().toUtc().toIso8601String(),
        'is_used': false,
      }, onConflict: 'email',);
    } catch (_) {
      try {
        await supabase.from('allowed_signups').insert({
          'email': cleanEmail,
          'employee_id': id,
          'invited_by': _uid,
          'invited_at': DateTime.now().toUtc().toIso8601String(),
          'is_used': false,
        });
      } catch (_) {}
    }

    // Welcome email (best-effort).
    try {
      await supabase.functions.invoke('send-welcome-email', body: {
        'employee_id': id,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'email': cleanEmail,
        'job_title': jobTitle,
        'department': department,
        'start_date': DateTime.now().toIso8601String().split('T').first,
      },);
    } catch (_) {}
  }

  Future<void> updateEmployee(
    String id, {
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    String? department,
    String? jobTitle,
    required String location,
    required String status,
  }) async {
    await supabase.from('employees').update({
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'email': email.trim(),
      'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
      'department': department,
      'job_title': jobTitle,
      'location': location,
      'status': status,
    }).eq('id', id);
  }

  /// Optional milestone fields on the linked profile (edit form).
  Future<void> saveMilestones({String? userId, String? profileId, String? dob, String? joining}) async {
    if (userId == null && profileId == null) return;
    final updates = {'date_of_birth': (dob ?? '').isEmpty ? null : dob, 'joining_date': (joining ?? '').isEmpty ? null : joining};
    try {
      if (userId != null) {
        await supabase.from('profiles').update(updates).eq('user_id', userId);
      } else {
        await supabase.from('profiles').update(updates).eq('id', profileId!);
      }
    } catch (_) {}
  }

  Future<void> deactivate(String id, String? email) async {
    await supabase.from('employees').update({
      'status': 'inactive',
      'termination_date': DateTime.now().toIso8601String().split('T').first,
    }).eq('id', id);
    if (email != null && email.isNotEmpty) {
      try {
        await supabase.from('allowed_signups').update({'is_used': true}).eq('email', email.toLowerCase());
      } catch (_) {}
    }
  }

  Future<void> reactivate(String id, String? email) async {
    await supabase.from('employees').update({
      'status': 'active',
      'termination_date': null,
    }).eq('id', id);
    if (email != null && email.isNotEmpty) {
      try {
        await supabase.from('allowed_signups').upsert({
          'email': email.toLowerCase(),
          'is_used': false,
          'invited_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'email',);
      } catch (_) {}
    }
  }
}
