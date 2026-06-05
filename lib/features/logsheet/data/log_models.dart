/// Work log (work_logs row) + client + department helpers for the Log Sheet.
library;

class WorkLog {
  const WorkLog({
    required this.id,
    required this.userId,
    this.employeeId,
    this.clientId,
    this.clientName,
    this.clientCode,
    this.department,
    required this.logDate,
    required this.taskDescription,
    this.timeSpentMinutes = 0,
    this.notes,
    this.startTime,
    this.endTime,
    this.status,
    this.pauseStart,
    this.totalPauseMinutes = 0,
    this.employeeName,
    this.employeeDept,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String? employeeId;
  final String? clientId;
  final String? clientName;
  final String? clientCode;
  final String? department; // stored task-department value e.g. "Tax_Preparation"
  final String logDate; // YYYY-MM-DD
  final String taskDescription;
  final int timeSpentMinutes;
  final String? notes;
  final String? startTime; // HH:mm
  final String? endTime; // HH:mm
  final String? status; // in_progress | on_hold | completed
  final DateTime? pauseStart;
  final int totalPauseMinutes;
  final String? employeeName; // from employee join (team views)
  final String? employeeDept; // employee profile department (report table)
  final DateTime? createdAt;

  bool get isActive => status == 'in_progress';
  bool get isOnHold => status == 'on_hold';
  bool get isDone => status == 'completed';

  String get statusLabel => switch (status) {
        'in_progress' => 'Active',
        'on_hold' => 'On Hold',
        'completed' => 'Done',
        _ => 'Done',
      };

  factory WorkLog.fromMap(Map<String, dynamic> m) {
    final client = m['client'] as Map?;
    final emp = m['employee'] as Map?;
    return WorkLog(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      employeeId: m['employee_id'] as String?,
      clientId: m['client_id'] as String?,
      clientName: client?['name'] as String?,
      clientCode: client?['client_id'] as String?,
      department: m['department'] as String?,
      logDate: (m['log_date'] ?? '') as String,
      taskDescription: (m['task_description'] ?? '') as String,
      timeSpentMinutes: ((m['time_spent_minutes'] ?? 0) as num).toInt(),
      notes: m['notes'] as String?,
      startTime: m['start_time'] as String?,
      endTime: m['end_time'] as String?,
      status: m['status'] as String?,
      pauseStart: m['pause_start'] != null
          ? DateTime.tryParse(m['pause_start'] as String)?.toUtc()
          : null,
      totalPauseMinutes: ((m['total_pause_minutes'] ?? 0) as num).toInt(),
      employeeName: emp != null
          ? '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim()
          : null,
      employeeDept: emp?['department'] as String?,
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
          : null,
    );
  }
}

/// Employee row for the report Employee filter.
class LogEmployee {
  const LogEmployee({
    required this.id,
    required this.name,
    this.employeeId,
    this.department,
    this.email,
  });
  final String id;
  final String name;
  final String? employeeId;
  final String? department;
  final String? email;

  String get display => employeeId != null && employeeId!.isNotEmpty
      ? '$name ($employeeId)'
      : name;

  factory LogEmployee.fromMap(Map<String, dynamic> m) => LogEmployee(
        id: m['id'] as String,
        name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
        employeeId: m['employee_id'] as String?,
        department: m['department'] as String?,
        email: m['email'] as String?,
      );
}

class Client {
  const Client({required this.id, required this.name, this.code});
  final String id;
  final String name;
  final String? code; // client_id business code

  String get display => code != null && code!.isNotEmpty ? '$name ($code)' : name;

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        code: m['client_id'] as String?,
      );
}

/// Formats minutes as "1h 30m" / "45m".
String formatMinutes(int min) {
  if (min <= 0) return '0m';
  final h = min ~/ 60;
  final m = min % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Minutes between two HH:mm strings (wraps past midnight).
int minutesBetween(String? start, String? end) {
  final s = _parseHm(start);
  final e = _parseHm(end);
  if (s == null || e == null) return 0;
  var d = e - s;
  if (d < 0) d += 1440;
  return d;
}

int? _parseHm(String? hm) {
  if (hm == null || !hm.contains(':')) return null;
  final p = hm.split(':');
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// A department node (parent group with optional children), mirroring the web
/// `DEPARTMENTS` array EXACTLY (label + DB value codes must match so filtering
/// and labels work against existing work_logs.department data).
class DeptNode {
  const DeptNode(this.label, this.value, [this.children = const []]);
  final String label;
  final String value;
  final List<DeptNode> children;
}

const kDepartmentTree = <DeptNode>[
  DeptNode('Tax', 'Tax', [
    DeptNode('Tax', 'Tax'),
    DeptNode('Tax Preparation', 'Tax_Preparation'),
    DeptNode('Tax Return Review', 'Tax_Return_Review'),
    DeptNode('Tax Return Walk Through', 'Tax_Return_Walk_Through'),
    DeptNode('Tax Return Compliance', 'Tax_Return_Compliance'),
    DeptNode('TR Closure', 'TR_Closure'),
    DeptNode('TR Invoicing', 'TR_Invoicing'),
    DeptNode('Final Review', 'Final_Review'),
    DeptNode('Tax Filing', 'Tax_Filing'),
  ]),
  DeptNode('Payroll', 'Payroll', [
    DeptNode('Payroll', 'Payroll_'),
    DeptNode('Payroll Preparation', 'Payroll_Preparation'),
    DeptNode('Payroll Notice Resolution', 'Payroll_Notice_Resolution'),
    DeptNode('Payroll Documentation', 'Payroll_Documentation'),
  ]),
  DeptNode('Accounting', 'Accounting', [
    DeptNode('Accounting', 'Accounting'),
    DeptNode('Daily Bookkeeping', 'Daily_Bookkeeping'),
    DeptNode('Book Closing', 'Month_End_Closing'),
    DeptNode('Book Review', 'Book_Review'),
    DeptNode('Book Discussion with Client', 'Book_Discussion_with_Client'),
    DeptNode('Sales Tax Preparation & Filing', 'Sales_Tax_Preparation_Filing'),
    DeptNode('Sales Tax Notice Resolution', 'Sales_Tax_Notice_Resolution'),
    DeptNode('Ad Hoc Request', 'Ad_hoc_requests'),
    DeptNode('Client Communication', 'Client_communications'),
    DeptNode('Reporting', 'Reporting'),
  ]),
  DeptNode('Marketing', 'Marketing'),
  DeptNode('Sales', 'Sales'),
  DeptNode('Human Resources', 'Human Resources'),
  DeptNode('Finance', 'Finance'),
  DeptNode('Operations', 'Operations'),
  DeptNode('Design', 'Design'),
  DeptNode('Customer Support', 'Customer Support'),
  DeptNode('Legal', 'Legal'),
  DeptNode('Engineering', 'Engineering'),
  DeptNode('Product', 'Product'),
  DeptNode('Other', 'Other'),
];

class DeptOption {
  const DeptOption(this.value, this.label);
  final String value;
  final String label;
}

/// Flat selectable options (the leaf/standalone values), with display labels
/// "Parent → Child" — matches the values React actually selects/stores.
final List<DeptOption> kDepartmentOptions = [
  for (final group in kDepartmentTree)
    if (group.children.isEmpty)
      DeptOption(group.value, group.label)
    else
      for (final child in group.children)
        DeptOption(
          child.value,
          child.label == group.label ? child.label : '${group.label} → ${child.label}',
        ),
];

/// Display label for a stored department value (web getDepartmentDisplayLabel).
String? getDepartmentDisplayLabel(String value) {
  for (final dept in kDepartmentTree) {
    if (dept.value == value) return dept.label;
    for (final child in dept.children) {
      if (child.value == value) return '${dept.label} → ${child.label}';
    }
  }
  return null;
}

String departmentLabel(String? value) {
  if (value == null || value.isEmpty) return '—';
  return getDepartmentDisplayLabel(value) ?? value.replaceAll('_', ' ');
}
