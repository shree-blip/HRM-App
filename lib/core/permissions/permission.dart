/// Ported 1:1 from the React `usePermissions.ts` `Permission` union, labels,
/// categories and route map. Keeping these identical guarantees the mobile
/// app makes the same client-side access decisions as the web app (the DB
/// `role_permissions` / `user_permission_overrides` tables are the source of
/// truth and are unchanged).
enum Permission {
  manageAccess('manage_access'),
  manageEmployees('manage_employees'),
  viewEmployeesAll('view_employees_all'),
  viewEmployeesReportsOnly('view_employees_reports_only'),
  viewAttendanceAll('view_attendance_all'),
  viewAttendanceReportsOnly('view_attendance_reports_only'),
  viewOwnAttendance('view_own_attendance'),
  editAttendance('edit_attendance'),
  manageSalariesAll('manage_salaries_all'),
  addAnnouncement('add_announcement'),
  editAnnouncement('edit_announcement'),
  deleteAnnouncement('delete_announcement'),
  viewAnnouncements('view_announcements'),
  manageDocuments('manage_documents'),
  viewDocuments('view_documents'),
  approveLeave('approve_leave'),
  viewLeave('view_leave'),
  viewReports('view_reports'),
  managePayroll('manage_payroll'),
  viewPayroll('view_payroll'),
  viewPayslips('view_payslips'),
  manageOnboarding('manage_onboarding'),
  viewOnboarding('view_onboarding'),
  manageTasks('manage_tasks'),
  viewTasks('view_tasks'),
  manageLoans('manage_loans'),
  viewLoans('view_loans'),
  manageCalendar('manage_calendar'),
  manageSupport('manage_support'),
  viewSupport('view_support'),
  viewBugReports('view_bug_reports'),
  submitBugReports('submit_bug_reports'),
  viewGrievances('view_grievances'),
  submitGrievances('submit_grievances'),
  viewAssetRequests('view_asset_requests'),
  submitAssetRequests('submit_asset_requests'),
  viewInvoices('view_invoices'),
  manageInvoices('manage_invoices'),
  viewLogSheet('view_log_sheet'),
  viewPerformance('view_performance');

  const Permission(this.key);

  /// The DB permission string stored in `role_permissions.permission`.
  final String key;

  static Permission? fromKey(String key) {
    for (final p in Permission.values) {
      if (p.key == key) return p;
    }
    return null;
  }
}

const Map<Permission, String> kPermissionLabels = {
  Permission.manageAccess: 'Manage Access Control',
  Permission.manageEmployees: 'Manage Employees',
  Permission.viewEmployeesAll: 'View All Employees',
  Permission.viewEmployeesReportsOnly: 'View Direct Reports Only',
  Permission.viewAttendanceAll: 'View All Attendance',
  Permission.viewAttendanceReportsOnly: 'View Reports Attendance',
  Permission.viewOwnAttendance: 'View Own Attendance',
  Permission.editAttendance: 'Edit Attendance Records',
  Permission.manageSalariesAll: 'Manage Salaries',
  Permission.addAnnouncement: 'Add Announcement',
  Permission.editAnnouncement: 'Edit Announcement',
  Permission.deleteAnnouncement: 'Delete Announcement',
  Permission.viewAnnouncements: 'View Announcements',
  Permission.manageDocuments: 'Manage Documents',
  Permission.viewDocuments: 'View Documents',
  Permission.approveLeave: 'Approve / Reject Leave',
  Permission.viewLeave: 'View Leave & Balances',
  Permission.viewReports: 'View Reports',
  Permission.managePayroll: 'Manage Payroll',
  Permission.viewPayroll: 'View Payroll',
  Permission.viewPayslips: 'View Own Payslips',
  Permission.manageOnboarding: 'Manage Onboarding',
  Permission.viewOnboarding: 'View Own Onboarding',
  Permission.manageTasks: 'Manage Tasks',
  Permission.viewTasks: 'View Tasks',
  Permission.manageLoans: 'Manage Loans',
  Permission.viewLoans: 'View Loans',
  Permission.manageCalendar: 'Manage Calendar Events',
  Permission.manageSupport: 'Manage Support (Full)',
  Permission.viewSupport: 'View Support',
  Permission.viewBugReports: 'View Bug Reports',
  Permission.submitBugReports: 'Submit Bug Reports',
  Permission.viewGrievances: 'View Grievances',
  Permission.submitGrievances: 'Submit Grievances',
  Permission.viewAssetRequests: 'View Asset Requests',
  Permission.submitAssetRequests: 'Submit Asset Requests',
  Permission.viewInvoices: 'View Invoices',
  Permission.manageInvoices: 'Manage Invoices',
  Permission.viewLogSheet: 'View Log Sheet',
  Permission.viewPerformance: 'View Performance',
};

/// Maps an app route to the permission(s) that unlock it. A user needs at
/// least ONE of the listed permissions (matches React `hasRouteAccess`).
const Map<String, List<Permission>> kRoutePermissions = {
  '/announcements': [
    Permission.addAnnouncement,
    Permission.editAnnouncement,
    Permission.deleteAnnouncement,
    Permission.viewAnnouncements,
  ],
  '/employees': [
    Permission.manageEmployees,
    Permission.viewEmployeesAll,
    Permission.viewEmployeesReportsOnly,
  ],
  '/approvals': [Permission.approveLeave],
  '/reports': [Permission.viewReports],
  '/payroll': [
    Permission.managePayroll,
    Permission.viewPayroll,
    Permission.viewPayslips,
  ],
  '/my-payslips': [Permission.viewPayslips],
  '/onboarding': [Permission.manageOnboarding],
  '/my-onboarding': [Permission.viewOnboarding],
  '/my-offboarding': [Permission.viewOnboarding],
  '/access-control': [Permission.manageAccess],
  '/attendance': [
    Permission.viewAttendanceAll,
    Permission.viewAttendanceReportsOnly,
    Permission.viewOwnAttendance,
  ],
  '/leave': [Permission.viewLeave, Permission.approveLeave],
  '/documents': [Permission.manageDocuments, Permission.viewDocuments],
  '/loans': [Permission.manageLoans, Permission.viewLoans],
  '/tasks': [Permission.manageTasks, Permission.viewTasks],
  '/support': [
    Permission.manageSupport,
    Permission.viewSupport,
    Permission.viewBugReports,
    Permission.submitBugReports,
    Permission.viewGrievances,
    Permission.submitGrievances,
    Permission.viewAssetRequests,
    Permission.submitAssetRequests,
  ],
  '/invoices': [Permission.viewInvoices, Permission.manageInvoices],
  '/log-sheet': [Permission.viewLogSheet],
  '/performance': [Permission.viewPerformance],
};
