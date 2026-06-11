import 'package:flutter/material.dart';

import '../permissions/permission.dart';
import '../permissions/permissions_controller.dart';

/// A single navigation destination, ported from the React `Sidebar.tsx`
/// `ALL_MENU_ITEMS`. Visibility is driven by effective permissions.
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.permissions,
    this.alwaysVisible = false,
    this.hideIfHas,
    this.phase,
  });

  final String label;
  final IconData icon;
  final String route;

  /// User needs at least ONE of these to see the item.
  final List<Permission>? permissions;

  /// Always shown to authenticated users.
  final bool alwaysVisible;

  /// Hide when the user has ANY of these (e.g. hide "My Onboarding" from admins).
  final List<Permission>? hideIfHas;

  /// Phase in which the destination ships (used by the placeholder screen).
  final int? phase;

  bool isVisible(PermissionsState perms) {
    if (hideIfHas != null && perms.hasAny(hideIfHas!)) return false;
    if (alwaysVisible) return true;
    if (permissions != null && perms.hasAny(permissions!)) return true;
    return false;
  }
}

/// The unified menu. Order mirrors the web sidebar.
const List<NavItem> kNavItems = [
  NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    route: '/',
    alwaysVisible: true,
  ),
  NavItem(
    label: 'Log Sheet',
    icon: Icons.assignment_outlined,
    route: '/log-sheet',
    permissions: [Permission.viewLogSheet],
  ),
  NavItem(
    label: 'Attendance',
    icon: Icons.access_time,
    route: '/attendance',
    permissions: [
      Permission.viewAttendanceAll,
      Permission.viewAttendanceReportsOnly,
      Permission.viewOwnAttendance,
    ],
    phase: 4,
  ),
  NavItem(
    label: 'Leave',
    icon: Icons.event_available_outlined,
    route: '/leave',
    permissions: [Permission.viewLeave, Permission.approveLeave],
    phase: 5,
  ),
  NavItem(
    label: 'Approvals',
    icon: Icons.fact_check_outlined,
    route: '/approvals',
    permissions: [Permission.approveLeave],
    phase: 6,
  ),
  NavItem(
    label: 'Team',
    icon: Icons.people_outline,
    route: '/employees',
    permissions: [
      Permission.manageEmployees,
      Permission.viewEmployeesAll,
      Permission.viewEmployeesReportsOnly,
    ],
    phase: 3,
  ),
  NavItem(
    label: 'Reports',
    icon: Icons.trending_up,
    route: '/reports',
    permissions: [Permission.viewReports],
    phase: 7,
  ),
  NavItem(
    label: 'Documents',
    icon: Icons.folder_outlined,
    route: '/documents',
    permissions: [Permission.manageDocuments, Permission.viewDocuments],
  ),
  NavItem(
    label: 'Support',
    icon: Icons.bug_report_outlined,
    route: '/support',
    permissions: [Permission.manageSupport, Permission.viewSupport],
  ),
  NavItem(
    label: 'Announcements',
    icon: Icons.campaign_outlined,
    route: '/announcements',
    permissions: [
      Permission.addAnnouncement,
      Permission.editAnnouncement,
      Permission.deleteAnnouncement,
      Permission.viewAnnouncements,
    ],
  ),
  NavItem(
    label: 'Tasks',
    icon: Icons.check_box_outlined,
    route: '/tasks',
    permissions: [Permission.manageTasks, Permission.viewTasks],
  ),
  NavItem(
    label: 'Invoices',
    icon: Icons.receipt_long_outlined,
    route: '/invoices',
    permissions: [Permission.viewInvoices, Permission.manageInvoices],
  ),
  NavItem(
    label: 'Hiring',
    icon: Icons.work_outline,
    route: '/hiring',
    alwaysVisible: true,
  ),
  NavItem(
    label: 'Onboarding',
    icon: Icons.person_add_alt_1_outlined,
    route: '/onboarding',
    permissions: [Permission.manageOnboarding],
  ),
  NavItem(
    label: 'My Onboarding',
    icon: Icons.person_add_alt_1_outlined,
    route: '/my-onboarding',
    permissions: [Permission.viewOnboarding],
    hideIfHas: [Permission.manageOnboarding],
  ),
  NavItem(
    label: 'My Offboarding',
    icon: Icons.person_remove_outlined,
    route: '/my-offboarding',
    permissions: [Permission.viewOnboarding],
    hideIfHas: [Permission.manageOnboarding],
  ),
  // Payroll & My Payslips are intentionally excluded from the mobile app —
  // no nav item and no route.
  NavItem(
    label: 'Loans',
    icon: Icons.account_balance_outlined,
    route: '/loans',
    permissions: [Permission.manageLoans, Permission.viewLoans],
  ),
  NavItem(
    label: 'Access Control',
    icon: Icons.shield_outlined,
    route: '/access-control',
    permissions: [Permission.manageAccess],
  ),
  NavItem(
    label: 'Timezones',
    icon: Icons.public,
    route: '/timezone-management',
    permissions: [Permission.manageAccess],
  ),
  NavItem(
    label: 'Profile',
    icon: Icons.account_circle_outlined,
    route: '/profile',
    alwaysVisible: true,
  ),
  NavItem(
    label: 'Settings',
    icon: Icons.settings_outlined,
    route: '/settings',
    alwaysVisible: true,
  ),
];

/// Routes that the dashboard's stat cards / drawer may navigate to but which
/// are not yet implemented — used to title the placeholder screen. Empty now:
/// every working web page is implemented; Payroll/Payslips are intentionally
/// excluded from mobile and Performance is Coming Soon on the web too.
const Map<String, ({String title, int phase})> kPlaceholderRoutes = {};
