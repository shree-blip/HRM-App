import 'package:flutter/material.dart';

/// Onboarding/offboarding models — ported from the web useOnboarding hook +
/// MyOnboarding / MyOffboarding pages. No schema changes.

const List<String> kOnbDepartments = [
  'Executive', 'Accounting', 'Tax', 'Operations', 'Marketing', 'IT',
  'Human Resources', 'Sales', 'Customer Support', 'Finance', 'Legal',
];

const List<({String value, String label})> kPayTypes = [
  (value: 'salary', label: 'Salary'),
  (value: 'hourly', label: 'Hourly'),
  (value: 'contractor', label: 'Contractor'),
];

/// Default tasks created with every new onboarding workflow (matches the hook).
const List<({String title, String description, String taskType, int sortOrder})> kDefaultOnboardingTasks = [
  (title: 'Send Offer Letter', description: 'Generate and send offer letter for signature', taskType: 'offer_letter', sortOrder: 1),
  (title: 'Background Check', description: 'Initiate background verification process', taskType: 'background_check', sortOrder: 2),
  (title: 'Sign NDA & Contracts', description: 'Collect signed NDA and employment contract', taskType: 'nda', sortOrder: 3),
  (title: 'IT Setup Request', description: 'Request equipment and system access', taskType: 'it_setup', sortOrder: 4),
  (title: 'Schedule Orientation', description: 'Schedule onboarding orientation session', taskType: 'orientation', sortOrder: 5),
  (title: 'Setup Direct Deposit', description: 'Collect Payroll processing info', taskType: 'general', sortOrder: 7),
  (title: 'Assign Mentor/Buddy', description: 'Pair new hire with a team member for guidance', taskType: 'general', sortOrder: 8),
];

IconData onboardingTaskIcon(String taskType) {
  switch (taskType) {
    case 'offer_letter':
      return Icons.description_outlined;
    case 'background_check':
      return Icons.verified_user_outlined;
    case 'nda':
      return Icons.assignment_outlined;
    case 'it_setup':
      return Icons.computer_outlined;
    case 'orientation':
      return Icons.menu_book_outlined;
    default:
      return Icons.group_outlined;
  }
}

String onboardingStatusLabel(String status) =>
    status == 'in-progress' ? 'In Progress' : (status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1));

class EmployeeBrief {
  const EmployeeBrief({required this.id, this.firstName = '', this.lastName = '', this.jobTitle, this.department, this.email});
  final String id;
  final String firstName;
  final String lastName;
  final String? jobTitle;
  final String? department;
  final String? email;
  String get fullName => '$firstName $lastName'.trim();
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();

  factory EmployeeBrief.fromMap(Map<String, dynamic> m) => EmployeeBrief(
        id: (m['id'] ?? '') as String,
        firstName: (m['first_name'] ?? '') as String,
        lastName: (m['last_name'] ?? '') as String,
        jobTitle: m['job_title'] as String?,
        department: m['department'] as String?,
        email: m['email'] as String?,
      );
}

class OnboardingTask {
  const OnboardingTask({
    required this.id,
    required this.title,
    this.description,
    required this.taskType,
    required this.isCompleted,
    this.completedAt,
    required this.sortOrder,
  });
  final String id;
  final String title;
  final String? description;
  final String taskType;
  final bool isCompleted;
  final String? completedAt;
  final int sortOrder;

  factory OnboardingTask.fromMap(Map<String, dynamic> m) => OnboardingTask(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: m['description'] as String?,
        taskType: (m['task_type'] ?? 'general') as String,
        isCompleted: m['is_completed'] == true,
        completedAt: m['completed_at'] as String?,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class OnboardingWorkflow {
  OnboardingWorkflow({
    required this.id,
    required this.employeeId,
    required this.startDate,
    this.targetCompletionDate,
    required this.status,
    this.completedAt,
    this.employee,
    this.tasks = const [],
  });
  final String id;
  final String employeeId;
  final String startDate;
  final String? targetCompletionDate;
  final String status;
  final String? completedAt;
  final EmployeeBrief? employee;
  final List<OnboardingTask> tasks;

  int get progress {
    if (tasks.isEmpty) return 0;
    final done = tasks.where((t) => t.isCompleted).length;
    return ((done / tasks.length) * 100).round();
  }

  int get completedCount => tasks.where((t) => t.isCompleted).length;

  factory OnboardingWorkflow.fromMap(Map<String, dynamic> m, {EmployeeBrief? employee, List<OnboardingTask> tasks = const []}) =>
      OnboardingWorkflow(
        id: (m['id'] ?? '') as String,
        employeeId: (m['employee_id'] ?? '') as String,
        startDate: (m['start_date'] ?? '') as String,
        targetCompletionDate: m['target_completion_date'] as String?,
        status: (m['status'] ?? 'pending') as String,
        completedAt: m['completed_at'] as String?,
        employee: employee,
        tasks: tasks,
      );
}

class OffboardingWorkflow {
  const OffboardingWorkflow({
    required this.id,
    required this.employeeId,
    this.resignationDate,
    required this.lastWorkingDate,
    this.reason,
    required this.status,
    required this.exitInterview,
    required this.assetsRecovered,
    required this.accessRevoked,
    required this.finalSettlement,
  });
  final String id;
  final String employeeId;
  final String? resignationDate;
  final String lastWorkingDate;
  final String? reason;
  final String status;
  final bool exitInterview;
  final bool assetsRecovered;
  final bool accessRevoked;
  final bool finalSettlement;

  int get progress {
    final items = [exitInterview, assetsRecovered, accessRevoked, finalSettlement];
    return ((items.where((b) => b).length / items.length) * 100).round();
  }

  factory OffboardingWorkflow.fromMap(Map<String, dynamic> m) => OffboardingWorkflow(
        id: (m['id'] ?? '') as String,
        employeeId: (m['employee_id'] ?? '') as String,
        resignationDate: m['resignation_date'] as String?,
        lastWorkingDate: (m['last_working_date'] ?? '') as String,
        reason: m['reason'] as String?,
        status: (m['status'] ?? 'pending') as String,
        exitInterview: m['exit_interview_completed'] == true,
        assetsRecovered: m['assets_recovered'] == true,
        accessRevoked: m['access_revoked'] == true,
        finalSettlement: m['final_settlement_processed'] == true,
      );
}

/// The four offboarding checklist steps (key + label + description + icon).
const List<({String key, String label, String description, IconData icon})> kOffboardingStepDefs = [
  (key: 'exit_interview_completed', label: 'Exit Interview', description: 'Schedule and conduct exit interview', icon: Icons.forum_outlined),
  (key: 'assets_recovered', label: 'Assets Recovered', description: 'Collect company equipment and badges', icon: Icons.inventory_2_outlined),
  (key: 'access_revoked', label: 'Access Revoked', description: 'Disable system access and credentials', icon: Icons.gpp_bad_outlined),
  (key: 'final_settlement_processed', label: 'Final Settlement', description: 'Process final paycheck and benefits', icon: Icons.payments_outlined),
];

class NewHireData {
  const NewHireData({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    required this.role,
    required this.department,
    required this.location,
    required this.startDate,
    this.salary,
    this.payType = 'salary',
  });
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String role;
  final String department;
  final String location;
  final String startDate;
  final double? salary;
  final String payType;
}
