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
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'] as String)?.toUtc()
          : null,
    );
  }
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

/// Department groups (mirrors the hardcoded nesting in the web LogSheet).
const kDepartmentGroups = <String, List<String>>{
  'Tax': [
    'Tax', 'Tax Preparation', 'Tax Return Review', 'Tax Return Walk Through',
    'Tax Return Compliance', 'TR Closure', 'TR Invoicing', 'Final Review',
    'Tax Filing',
  ],
  'Payroll': [
    'Payroll', 'Payroll Preparation', 'Payroll Notice Resolution',
    'Payroll Documentation',
  ],
  'Accounting': [
    'Accounting', 'Daily Bookkeeping', 'Book Closing', 'Book Review',
    'Book Discussion with Client', 'Sales Tax Preparation & Filing',
    'Sales Tax Notice Resolution', 'Ad Hoc Request', 'Client Communication',
    'Reporting',
  ],
  'Marketing': [],
  'Sales': [],
  'Finance': [],
  'Operations': [],
  'Design': [],
  'Engineering': [],
  'Human Resources': [],
  'Customer Support': [],
  'Legal': [],
  'Product': [],
  'Other': [],
};

class DeptOption {
  const DeptOption(this.value, this.label);
  final String value;
  final String label;
}

final List<DeptOption> kDepartmentOptions = [
  for (final entry in kDepartmentGroups.entries)
    if (entry.value.isEmpty)
      DeptOption(entry.key, entry.key)
    else
      for (final child in entry.value)
        DeptOption(
          child.replaceAll(' ', '_'),
          child == entry.key ? child : '${entry.key} → $child',
        ),
];

String departmentLabel(String? value) {
  if (value == null || value.isEmpty) return '—';
  for (final o in kDepartmentOptions) {
    if (o.value == value) return o.label;
  }
  return value.replaceAll('_', ' ');
}
