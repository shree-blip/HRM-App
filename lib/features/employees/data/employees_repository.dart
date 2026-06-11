import '../../../core/supabase/supabase_client.dart';
import 'employee.dart';
import 'team_models.dart';

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

  // ── Team / profile relations (parity with EmployeeProfileDialog) ──
  static const _teamCols = 'id, first_name, last_name, email, department, job_title, status';

  /// People who report to [employeeId] — junction table + legacy
  /// line_manager_id / manager_id columns, deduplicated and name-sorted.
  Future<List<TeamMember>> fetchCombinedTeam(String employeeId) async {
    final junction = await supabase
        .from('team_members')
        .select('member_employee_id')
        .eq('manager_employee_id', employeeId);
    final junctionIds = (junction as List)
        .map((r) => (r as Map)['member_employee_id'] as String?)
        .whereType<String>()
        .toList();

    final line = await supabase.from('employees').select(_teamCols).eq('line_manager_id', employeeId);
    final mgr = await supabase.from('employees').select(_teamCols).eq('manager_id', employeeId);

    final byId = <String, TeamMember>{};
    for (final r in [...line as List, ...mgr as List]) {
      final m = TeamMember.fromMap((r as Map).cast<String, dynamic>());
      if (m.id.isNotEmpty) byId[m.id] = m;
    }
    final missing = junctionIds.where((id) => !byId.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final extra = await supabase.from('employees').select(_teamCols).inFilter('id', missing);
      for (final r in extra as List) {
        final m = TeamMember.fromMap((r as Map).cast<String, dynamic>());
        if (m.id.isNotEmpty) byId[m.id] = m;
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
    return list;
  }

  /// Which of [employeeIds] are themselves managers (have a sub-team) — used
  /// to show the "Team Lead" badge + drill-down affordance.
  Future<Set<String>> detectManagers(List<String> employeeIds) async {
    if (employeeIds.isEmpty) return {};
    final ids = <String>{};
    final j = await supabase.from('team_members').select('manager_employee_id').inFilter('manager_employee_id', employeeIds);
    for (final r in j as List) {
      final v = (r as Map)['manager_employee_id'] as String?;
      if (v != null) ids.add(v);
    }
    final lm = await supabase.from('employees').select('line_manager_id').inFilter('line_manager_id', employeeIds);
    for (final r in lm as List) {
      final v = (r as Map)['line_manager_id'] as String?;
      if (v != null) ids.add(v);
    }
    final mm = await supabase.from('employees').select('manager_id').inFilter('manager_id', employeeIds);
    for (final r in mm as List) {
      final v = (r as Map)['manager_id'] as String?;
      if (v != null) ids.add(v);
    }
    return ids;
  }

  /// Managers an employee reports to ("Reports To"), from the junction table.
  Future<List<ManagerRef>> managersOf(String employeeId) async {
    final rows = await supabase
        .from('team_members')
        .select('manager_employee_id')
        .eq('member_employee_id', employeeId);
    final ids = (rows as List)
        .map((r) => (r as Map)['manager_employee_id'] as String?)
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return [];
    final mgrs = await supabase
        .from('employees')
        .select('id, first_name, last_name, email, job_title, department')
        .inFilter('id', ids)
        .order('first_name', ascending: true);
    return (mgrs as List)
        .map((r) => ManagerRef.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Employees not yet on [managerId]'s team (for the Add-to-Team picker).
  Future<List<TeamMember>> availableForTeam(String managerId) async {
    final existing = await supabase
        .from('team_members')
        .select('member_employee_id')
        .eq('manager_employee_id', managerId);
    final taken = (existing as List)
        .map((r) => (r as Map)['member_employee_id'] as String?)
        .whereType<String>()
        .toSet();
    final rows = await supabase
        .from('employees')
        .select(_teamCols)
        .or('status.eq.active,status.is.null')
        .order('first_name', ascending: true);
    return (rows as List)
        .map((r) => TeamMember.fromMap((r as Map).cast<String, dynamic>()))
        .where((e) => e.id.isNotEmpty && e.id != managerId && !taken.contains(e.id))
        .toList();
  }

  /// Idempotent team assignment via the backend RPC (+ best-effort notify).
  Future<void> addTeamMember(String managerId, String memberId) async {
    await supabase.rpc('add_team_member', params: {
      '_manager_employee_id': managerId,
      '_member_employee_id': memberId,
    },);
    try {
      final emp = await supabase.from('employees').select('profile_id').eq('id', memberId).maybeSingle();
      final profileId = emp?['profile_id'] as String?;
      if (profileId != null) {
        final prof = await supabase.from('profiles').select('user_id').eq('id', profileId).maybeSingle();
        final userId = prof?['user_id'] as String?;
        if (userId != null) {
          await supabase.rpc('create_notification', params: {
            'p_user_id': userId,
            'p_title': '👥 Added to Team',
            'p_message': "You have been added to your manager's team.",
            'p_type': 'team',
            'p_link': '/employees',
          },);
        }
      }
    } catch (_) {}
    await _sendTeamAssignmentEmail(managerId, memberId);
  }

  /// Remove a member: delete junction row + clear legacy columns pointing here.
  Future<void> removeFromTeam(String managerId, String memberId) async {
    await supabase
        .from('team_members')
        .delete()
        .eq('manager_employee_id', managerId)
        .eq('member_employee_id', memberId);
    try {
      final row = await supabase
          .from('employees')
          .select('line_manager_id, manager_id')
          .eq('id', memberId)
          .maybeSingle();
      if (row != null) {
        final updates = <String, dynamic>{};
        if (row['line_manager_id'] == managerId) updates['line_manager_id'] = null;
        if (row['manager_id'] == managerId) updates['manager_id'] = null;
        if (updates.isNotEmpty) {
          await supabase.from('employees').update(updates).eq('id', memberId);
        }
      }
    } catch (_) {}
    await _sendTeamAssignmentEmail(managerId, memberId, action: 'removed');
  }

  /// Email to the affected employee — same edge function + payload as the
  /// web (AddToTeamDialog / Employees.tsx remove flow). Best-effort.
  Future<void> _sendTeamAssignmentEmail(
    String managerId,
    String memberId, {
    String? action,
  }) async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final assigner = await supabase
          .from('profiles')
          .select('first_name, last_name, email')
          .eq('user_id', uid)
          .maybeSingle();
      final member = await supabase
          .from('employees')
          .select('first_name, last_name, email')
          .eq('id', memberId)
          .maybeSingle();
      final manager = await supabase
          .from('employees')
          .select('first_name, last_name')
          .eq('id', managerId)
          .maybeSingle();
      if (member == null) return;
      final assignerName = assigner != null
          ? '${assigner['first_name'] ?? ''} ${assigner['last_name'] ?? ''}'.trim()
          : 'Executive';
      await supabase.functions.invoke('send-team-assignment-notification', body: {
        if (action != null) 'action': action,
        'assigner_name': assignerName.isEmpty ? 'Executive' : assignerName,
        'assigner_email': (assigner?['email'] ?? '') as String,
        'employee_name':
            '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim(),
        'employee_email': (member['email'] ?? '') as String,
        'manager_name': manager != null
            ? '${manager['first_name'] ?? ''} ${manager['last_name'] ?? ''}'.trim()
            : 'your manager',
      },);
    } catch (_) {}
  }

  /// Resolve the auth user_id behind a profile_id (for leave queries).
  Future<String?> userIdForProfile(String? profileId) async {
    if (profileId == null) return null;
    try {
      final r = await supabase.from('profiles').select('user_id').eq('id', profileId).maybeSingle();
      return r?['user_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Birthday / work anniversary from the linked profile.
  Future<EmployeeMilestones> milestones({String? userId, String? profileId}) async {
    if (userId == null && profileId == null) return const EmployeeMilestones();
    try {
      final q = supabase.from('profiles').select('date_of_birth, joining_date');
      final row = userId != null
          ? await q.eq('user_id', userId).maybeSingle()
          : await q.eq('id', profileId!).maybeSingle();
      if (row == null) return const EmployeeMilestones();
      return EmployeeMilestones(dob: row['date_of_birth'] as String?, joining: row['joining_date'] as String?);
    } catch (_) {
      return const EmployeeMilestones();
    }
  }

  /// Leave balances for the current fiscal year (Jul 1 – Jun 30), merging
  /// `leave_balances` with approved `leave_requests`, mirroring the web logic.
  Future<List<LeaveBalance>> leaveBalances(String userId, DateTime now) async {
    final fyStartYear = now.month >= 7 ? now.year : now.year - 1;
    final fyStart = '$fyStartYear-07-01';
    final fyEnd = '${fyStartYear + 1}-06-30';

    final balances = await supabase
        .from('leave_balances')
        .select('leave_type, total_days, used_days')
        .eq('user_id', userId)
        .eq('year', fyStartYear + 1);

    final approved = await supabase
        .from('leave_requests')
        .select('leave_type, days, is_half_day')
        .eq('user_id', userId)
        .eq('status', 'approved')
        .gte('start_date', fyStart)
        .lte('start_date', fyEnd);

    final usedMap = <String, double>{};
    for (final r in approved as List) {
      final m = r as Map;
      var type = (m['leave_type'] ?? '') as String;
      if (type.startsWith('Other Leave -')) {
        type = 'Other Leave';
      } else if (type.startsWith('Leave in Lieu')) {
        type = 'Leave in Lieu';
      }
      final isHalf = m['is_half_day'] == true;
      final days = isHalf ? 0.5 : ((m['days'] as num?)?.toDouble() ?? 0);
      usedMap[type] = (usedMap[type] ?? 0) + days;
    }

    final balanceMap = <String, ({double total, double used})>{};
    for (final b in balances as List) {
      final m = b as Map;
      balanceMap[(m['leave_type'] ?? '') as String] = (
        total: (m['total_days'] as num?)?.toDouble() ?? 0,
        used: (m['used_days'] as num?)?.toDouble() ?? 0,
      );
    }
    const subsumed = ['Sick Leave', 'Other Leave - Sick Leave', 'Other Leave'];
    usedMap.forEach((type, used) {
      if (!balanceMap.containsKey(type) && !subsumed.contains(type)) {
        balanceMap[type] = (total: 0, used: used);
      }
    });

    const hidden = ['Sick Leave', 'Personal Leave', 'Comp Time'];
    final out = <LeaveBalance>[];
    balanceMap.forEach((type, v) {
      if (hidden.contains(type)) return;
      out.add(LeaveBalance(leaveType: type, totalDays: v.total, usedDays: v.used));
    });
    const order = ['Annual Leave', 'Leave in Lieu'];
    out.sort((a, b) {
      final ai = order.indexOf(a.leaveType);
      final bi = order.indexOf(b.leaveType);
      return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
    });
    return out;
  }
}
