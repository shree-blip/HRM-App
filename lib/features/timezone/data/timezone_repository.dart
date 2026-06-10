import '../../../core/supabase/supabase_client.dart';
import 'timezone_models.dart';

/// Timezone Management data access — mirrors the web TimezoneManagement page.
/// No schema changes; updates `employees` + appends to `timezone_change_log`.
class TimezoneRepository {
  String get _uid => supabase.auth.currentUser!.id;

  Future<List<EmployeeTimezoneRow>> fetchEmployees() async {
    final rows = await supabase
        .from('employees')
        .select('id, first_name, last_name, department, job_title, timezone, timezone_status, email')
        .eq('status', 'active')
        .order('first_name');
    return (rows as List).map((r) => EmployeeTimezoneRow.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  /// Update one employee's timezone + log the change. Optionally mark verified.
  Future<void> updateTimezone({
    required EmployeeTimezoneRow employee,
    required String newTimezone,
    required String reason,
    required bool markVerified,
  }) async {
    final updates = <String, dynamic>{
      'timezone': newTimezone,
      'timezone_effective_from': DateTime.now().toIso8601String().split('T').first,
    };
    if (markVerified) {
      updates['timezone_status'] = 'verified';
      updates['timezone_verified_at'] = DateTime.now().toUtc().toIso8601String();
      updates['timezone_verified_by'] = _uid;
    }
    await supabase.from('employees').update(updates).eq('id', employee.id);
    await supabase.from('timezone_change_log').insert({
      'employee_id': employee.id,
      'old_timezone': employee.timezone,
      'new_timezone': newTimezone,
      'reason': reason,
      'changed_by': _uid,
    });
  }

  /// Bulk update many employees to one timezone (marks verified) + log each.
  Future<void> bulkUpdate({
    required List<EmployeeTimezoneRow> employees,
    required String newTimezone,
    required String reason,
  }) async {
    final ids = employees.map((e) => e.id).toList();
    await supabase.from('employees').update({
      'timezone': newTimezone,
      'timezone_status': 'verified',
      'timezone_verified_at': DateTime.now().toUtc().toIso8601String(),
      'timezone_verified_by': _uid,
      'timezone_effective_from': DateTime.now().toIso8601String().split('T').first,
    }).inFilter('id', ids);

    final logs = employees
        .map((e) => {
              'employee_id': e.id,
              'old_timezone': e.timezone,
              'new_timezone': newTimezone,
              'reason': reason,
              'changed_by': _uid,
            },)
        .toList();
    await supabase.from('timezone_change_log').insert(logs);
  }
}
