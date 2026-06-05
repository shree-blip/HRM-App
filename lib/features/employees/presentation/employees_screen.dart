import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../data/employee.dart';
import '../data/employees_providers.dart';
import 'widgets/employee_avatar.dart';

/// Read-only employee directory: searchable, filterable list (RLS-scoped).
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _department = 'all';
  String _location = 'all';

  static const _viewPerms = [
    Permission.manageEmployees,
    Permission.viewEmployeesAll,
    Permission.viewEmployeesReportsOnly,
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    // VP/Admin always have access (mirrors the web ProtectedRoute bypass).
    final canView = auth.isVp || auth.isAdmin || perms.hasAny(_viewPerms);
    // Don't flash "no access" while permissions are still loading.
    final stillResolving = perms.loading && !canView;
    final async = ref.watch(employeesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(employeesListProvider),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/employees'),
      body: stillResolving
          ? const Center(child: CircularProgressIndicator())
          : !canView
          ? const _NoAccess()
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                onRetry: () => ref.invalidate(employeesListProvider),
              ),
              data: (all) => _buildList(context, all),
            ),
    );
  }

  Widget _buildList(BuildContext context, List<EmployeeDirectoryItem> all) {
    final departments = <String>{
      for (final e in all)
        if (e.department != null && e.department!.isNotEmpty) e.department!,
    }.toList()
      ..sort();
    final locations = <String>{
      for (final e in all)
        if (e.location != null && e.location!.isNotEmpty) e.location!,
    }.toList()
      ..sort();

    final q = _query.toLowerCase();
    final filtered = all.where((e) {
      final matchesSearch = q.isEmpty ||
          e.fullName.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          (e.jobTitle ?? '').toLowerCase().contains(q);
      final matchesDept = _department == 'all' || e.department == _department;
      final matchesLoc = _location == 'all' || e.location == _location;
      return matchesSearch && matchesDept && matchesLoc;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search by name, email or role',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _FilterDropdown(
                icon: Icons.apartment_outlined,
                label: 'Department',
                value: _department,
                options: departments,
                onChanged: (v) => setState(() => _department = v),
              ),
              const SizedBox(width: 8),
              _FilterDropdown(
                icon: Icons.place_outlined,
                label: 'Location',
                value: _location,
                options: locations,
                onChanged: (v) => setState(() => _location = v),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Showing ${filtered.length} of ${all.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No employees found'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _EmployeeTile(employee: filtered[i]),
                ),
        ),
      ],
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile({required this.employee});
  final EmployeeDirectoryItem employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () =>
            context.go('/employees/${employee.id}', extra: employee),
        leading: EmployeeAvatar(initials: employee.initials, url: employee.avatarUrl),
        title: Text(employee.fullName,
            maxLines: 1, overflow: TextOverflow.ellipsis,),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              employee.jobTitle?.isNotEmpty == true
                  ? employee.jobTitle!
                  : employee.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (employee.department?.isNotEmpty == true) ...[
                  Flexible(
                    child: Text(
                      employee.department!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                EmployeeStatusChip(status: employee.displayStatus),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: true,
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              items: [
                DropdownMenuItem(value: 'all', child: Text('All ${label}s')),
                for (final o in options)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) => onChanged(v ?? 'all'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant,),
            const SizedBox(height: 12),
            const Text(
              "You don't have permission to view employees.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load employees.'),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
