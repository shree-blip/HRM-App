import '../../../core/supabase/supabase_client.dart';
import 'onboarding_models.dart';

/// Onboarding/offboarding data access — mirrors the web useOnboarding hook +
/// the MyOnboarding/MyOffboarding self-view queries. No schema changes.
class OnboardingRepository {
  String get _uid => supabase.auth.currentUser!.id;

  // ── Admin: fetch ──────────────────────────────────────
  Future<List<OnboardingWorkflow>> fetchOnboarding() async {
    final rows = await supabase
        .from('onboarding_workflows')
        .select('*, employees:employee_id (id, first_name, last_name, job_title, department, email)')
        .neq('status', 'cancelled')
        .order('created_at', ascending: false);

    final out = <OnboardingWorkflow>[];
    for (final r in rows as List) {
      final m = (r as Map).cast<String, dynamic>();
      final empMap = m['employees'];
      final employee = empMap is Map ? EmployeeBrief.fromMap(empMap.cast<String, dynamic>()) : null;
      final taskRows = await supabase
          .from('onboarding_tasks')
          .select('*')
          .eq('workflow_id', m['id'])
          .order('sort_order', ascending: true);
      final tasks = (taskRows as List).map((t) => OnboardingTask.fromMap((t as Map).cast<String, dynamic>())).toList();
      out.add(OnboardingWorkflow.fromMap(m, employee: employee, tasks: tasks));
    }
    return out;
  }

  Future<List<OffboardingWorkflow>> fetchOffboarding() async {
    final rows = await supabase
        .from('offboarding_workflows')
        .select('*')
        .neq('status', 'cancelled')
        .order('created_at', ascending: false);
    return (rows as List).map((r) => OffboardingWorkflow.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  // ── Admin: create new hire + onboarding ───────────────
  Future<void> createNewHireWithOnboarding(NewHireData d) async {
    final email = d.email.toLowerCase().trim();

    // Cross-system email check (best-effort).
    bool existsInAuth = false, existsInProfiles = false;
    try {
      final res = await supabase.rpc('check_email_registration', params: {'_email': email});
      if (res is Map) {
        existsInAuth = res['exists_in_auth'] == true;
        existsInProfiles = res['exists_in_profiles'] == true;
      }
    } catch (_) {}

    final existing = await supabase.from('employees').select('id, first_name, last_name').eq('email', email).maybeSingle();
    String employeeId;
    if (existing != null) {
      final active = await supabase
          .from('onboarding_workflows')
          .select('id')
          .eq('employee_id', existing['id'])
          .inFilter('status', ['pending', 'in-progress'])
          .maybeSingle();
      if (active != null) {
        throw Exception('${existing['first_name']} ${existing['last_name']} already has an active onboarding workflow.');
      }
      employeeId = existing['id'] as String;
    } else {
      if (existsInAuth || existsInProfiles) {
        throw Exception('This email is already registered.');
      }
      final emp = await supabase
          .from('employees')
          .insert({
            'first_name': d.firstName.trim(),
            'last_name': d.lastName.trim(),
            'email': email,
            'job_title': d.role.trim(),
            'department': d.department,
            'location': d.location,
            'phone': (d.phone == null || d.phone!.trim().isEmpty) ? null : d.phone!.trim(),
            'status': 'probation',
            'hire_date': d.startDate,
            'pay_type': d.payType,
            if (d.salary != null && d.payType == 'hourly') 'hourly_rate': d.salary,
            if (d.salary != null && d.payType != 'hourly') 'salary': d.salary,
          })
          .select('id')
          .single();
      employeeId = emp['id'] as String;
      // Welcome email (best-effort).
      try {
        await supabase.functions.invoke('send-welcome-email', body: {
          'employee_id': employeeId,
          'first_name': d.firstName,
          'last_name': d.lastName,
          'email': email,
          'job_title': d.role,
          'department': d.department,
          'start_date': d.startDate,
        },);
      } catch (_) {}
    }

    await _createWorkflowWithTasks(employeeId, d.startDate);
  }

  /// Onboarding for an existing employee.
  Future<void> createOnboarding(String employeeId, String startDate) async {
    final active = await supabase
        .from('onboarding_workflows')
        .select('id')
        .eq('employee_id', employeeId)
        .inFilter('status', ['pending', 'in-progress'])
        .maybeSingle();
    if (active != null) throw Exception('This employee already has an active onboarding workflow.');
    await _createWorkflowWithTasks(employeeId, startDate);
  }

  Future<void> _createWorkflowWithTasks(String employeeId, String startDate) async {
    final start = DateTime.tryParse(startDate) ?? DateTime.now();
    final target = start.add(const Duration(days: 14));
    final wf = await supabase
        .from('onboarding_workflows')
        .insert({
          'employee_id': employeeId,
          'start_date': startDate,
          'target_completion_date': target.toIso8601String().split('T').first,
          'status': 'pending',
          'created_by': _uid,
        })
        .select('id')
        .single();
    final wfId = wf['id'] as String;
    final tasks = kDefaultOnboardingTasks
        .map((t) => {
              'workflow_id': wfId,
              'title': t.title,
              'description': t.description,
              'task_type': t.taskType,
              'sort_order': t.sortOrder,
              'is_completed': false,
            },)
        .toList();
    await supabase.from('onboarding_tasks').insert(tasks);
  }

  // ── Admin: task toggle (with status + employee sync) ──
  Future<void> toggleTask(String taskId, bool currentlyCompleted) async {
    if (currentlyCompleted) {
      await _uncompleteTask(taskId);
    } else {
      await _completeTask(taskId);
    }
  }

  Future<void> _completeTask(String taskId) async {
    final task = await supabase.from('onboarding_tasks').select('workflow_id').eq('id', taskId).single();
    final wfId = task['workflow_id'] as String;
    await supabase.from('onboarding_tasks').update({
      'is_completed': true,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'completed_by': _uid,
    }).eq('id', taskId);

    final all = await supabase.from('onboarding_tasks').select('is_completed').eq('workflow_id', wfId);
    final list = all as List;
    final completed = list.where((t) => (t as Map)['is_completed'] == true).length;
    final total = list.length;

    String status = 'pending';
    String? completedAt;
    if (completed == total) {
      status = 'completed';
      completedAt = DateTime.now().toUtc().toIso8601String();
      final wf = await supabase.from('onboarding_workflows').select('employee_id').eq('id', wfId).single();
      final empId = wf['employee_id'] as String;
      await supabase.from('employees').update({'status': 'active'}).eq('id', empId);
      final emp = await supabase.from('employees').select('email').eq('id', empId).single();
      final email = emp['email'] as String?;
      if (email != null && email.isNotEmpty) {
        try {
          await supabase.from('allowed_signups').upsert({
            'email': email.toLowerCase(),
            'employee_id': empId,
            'invited_by': _uid,
            'invited_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'email',);
        } catch (_) {}
      }
    } else if (completed > 0) {
      status = 'in-progress';
    }
    await supabase.from('onboarding_workflows').update({'status': status, 'completed_at': completedAt}).eq('id', wfId);
  }

  Future<void> _uncompleteTask(String taskId) async {
    final task = await supabase.from('onboarding_tasks').select('workflow_id').eq('id', taskId).single();
    final wfId = task['workflow_id'] as String;
    await supabase.from('onboarding_tasks').update({
      'is_completed': false,
      'completed_at': null,
      'completed_by': null,
    }).eq('id', taskId);

    final all = await supabase.from('onboarding_tasks').select('is_completed').eq('workflow_id', wfId);
    final list = all as List;
    // Subtract the one we just reopened (matches the web logic).
    final completed = list.where((t) => (t as Map)['is_completed'] == true).length - 1;
    final status = completed > 0 ? 'in-progress' : 'pending';
    await supabase.from('onboarding_workflows').update({'status': status, 'completed_at': null}).eq('id', wfId);
    if (status == 'in-progress') {
      final wf = await supabase.from('onboarding_workflows').select('employee_id').eq('id', wfId).single();
      await supabase.from('employees').update({'status': 'probation'}).eq('id', wf['employee_id']);
    }
  }

  Future<void> deleteOnboarding(String workflowId) async {
    await supabase.from('onboarding_tasks').delete().eq('workflow_id', workflowId);
    await supabase.from('onboarding_workflows').delete().eq('id', workflowId);
  }

  Future<void> deleteOffboarding(String workflowId) async {
    await supabase.from('offboarding_workflows').delete().eq('id', workflowId);
  }

  // ── Admin: offboarding ────────────────────────────────
  Future<void> createOffboarding(String employeeId, String lastWorkingDate, String? reason) async {
    final existing = await supabase
        .from('offboarding_workflows')
        .select('id')
        .eq('employee_id', employeeId)
        .inFilter('status', ['pending', 'in-progress'])
        .maybeSingle();
    if (existing != null) throw Exception('This employee already has an active offboarding workflow.');
    await supabase.from('offboarding_workflows').insert({
      'employee_id': employeeId,
      'last_working_date': lastWorkingDate,
      'resignation_date': DateTime.now().toIso8601String().split('T').first,
      'reason': reason,
      'status': 'pending',
      'exit_interview_completed': false,
      'assets_recovered': false,
      'access_revoked': false,
      'final_settlement_processed': false,
      'created_by': _uid,
    });
  }

  /// Set one checklist boolean (one-way to true in the UI), recompute status,
  /// and mark employee inactive when all four complete — mirrors the web.
  Future<void> updateOffboarding(String workflowId, String key) async {
    final current = await supabase.from('offboarding_workflows').select('*').eq('id', workflowId).single();
    final merged = Map<String, dynamic>.from(current);
    merged[key] = true;

    final allComplete = merged['exit_interview_completed'] == true &&
        merged['assets_recovered'] == true &&
        merged['access_revoked'] == true &&
        merged['final_settlement_processed'] == true;
    final hasAny = merged['exit_interview_completed'] == true ||
        merged['assets_recovered'] == true ||
        merged['access_revoked'] == true ||
        merged['final_settlement_processed'] == true;
    final status = allComplete ? 'completed' : (hasAny ? 'in-progress' : 'pending');

    await supabase.from('offboarding_workflows').update({key: true, 'status': status}).eq('id', workflowId);

    if (allComplete && current['status'] != 'completed') {
      await supabase.from('employees').update({
        'status': 'inactive',
        'termination_date': DateTime.now().toIso8601String().split('T').first,
      }).eq('id', current['employee_id']);
    }
  }

  // ── Self view (MyOnboarding / MyOffboarding) ──────────
  Future<String?> _myEmployeeId() async {
    final profile = await supabase.from('profiles').select('id').eq('user_id', _uid).maybeSingle();
    if (profile == null) return null;
    final emp = await supabase.from('employees').select('id').eq('profile_id', profile['id']).maybeSingle();
    return emp?['id'] as String?;
  }

  Future<OnboardingWorkflow?> myOnboarding() async {
    final empId = await _myEmployeeId();
    if (empId == null) return null;
    final wf = await supabase
        .from('onboarding_workflows')
        .select('id, status, start_date, target_completion_date, completed_at, employee_id')
        .eq('employee_id', empId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (wf == null) return null;
    final taskRows = await supabase
        .from('onboarding_tasks')
        .select('id, title, description, task_type, is_completed, completed_at, sort_order')
        .eq('workflow_id', wf['id'])
        .order('sort_order', ascending: true);
    final tasks = (taskRows as List).map((t) => OnboardingTask.fromMap((t as Map).cast<String, dynamic>())).toList();
    return OnboardingWorkflow.fromMap(wf.cast<String, dynamic>(), tasks: tasks);
  }

  Future<OffboardingWorkflow?> myOffboarding() async {
    final empId = await _myEmployeeId();
    if (empId == null) return null;
    final wf = await supabase
        .from('offboarding_workflows')
        .select('*')
        .eq('employee_id', empId)
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (wf == null) return null;
    return OffboardingWorkflow.fromMap(wf.cast<String, dynamic>());
  }
}
