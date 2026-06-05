import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/employee.dart';
import '../data/employees_providers.dart';
import 'widgets/employee_avatar.dart';

/// Read-only employee profile: core info, who they report to, and their team.
class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId, this.initial});

  final String employeeId;

  /// Passed via navigation `extra` from the list to avoid a refetch.
  final EmployeeDirectoryItem? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initial != null) {
      return _DetailBody(employee: initial!);
    }
    final async = ref.watch(employeeByIdProvider(employeeId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(body: Center(child: Text('Could not load employee.'))),
      data: (e) => e == null
          ? const Scaffold(body: Center(child: Text('Employee not found.')))
          : _DetailBody(employee: e),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.employee});
  final EmployeeDirectoryItem employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final relations = ref.watch(employeeRelationsProvider(employee.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Employee')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              EmployeeAvatar(
                initials: employee.initials,
                url: employee.avatarUrl,
                radius: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employee.fullName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),),
                    const SizedBox(height: 2),
                    Text(
                      employee.jobTitle?.isNotEmpty == true
                          ? employee.jobTitle!
                          : 'Employee',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    EmployeeStatusChip(status: employee.displayStatus),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Info
          _InfoCard(employee: employee),
          const SizedBox(height: 16),

          // Relations
          relations.when(
            loading: () => const _RelationsLoading(),
            error: (_, __) => const SizedBox.shrink(),
            data: (rel) => Column(
              children: [
                _PeopleCard(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Reports To',
                  people: rel.managers,
                  emptyText: 'Not assigned to a manager.',
                ),
                const SizedBox(height: 16),
                _PeopleCard(
                  icon: Icons.groups_outlined,
                  title: 'Team (${rel.team.length})',
                  people: rel.team,
                  emptyText: 'No team members.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.employee});
  final EmployeeDirectoryItem employee;

  @override
  Widget build(BuildContext context) {
    final loc = switch (employee.location) {
      'US' => 'United States',
      'Nepal' => 'Nepal',
      _ => employee.location ?? '—',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Row(icon: Icons.mail_outline, label: 'Email', value: employee.email),
            _Row(
              icon: Icons.apartment_outlined,
              label: 'Department',
              value: employee.department?.isNotEmpty == true ? employee.department! : '—',
            ),
            _Row(icon: Icons.place_outlined, label: 'Location', value: loc),
            _Row(
              icon: Icons.event_outlined,
              label: 'Hire date',
              value: employee.hireDate?.isNotEmpty == true ? employee.hireDate! : '—',
            ),
            _Row(
              icon: Icons.verified_user_outlined,
              label: 'Account',
              value: employee.isRegistered ? 'Registered' : 'Pending signup',
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),),
          ),
        ],
      ),
    );
  }
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard({
    required this.icon,
    required this.title,
    required this.people,
    required this.emptyText,
  });

  final IconData icon;
  final String title;
  final List<EmployeeDirectoryItem> people;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),),
              ],
            ),
            const SizedBox(height: 8),
            if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(emptyText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),),
              )
            else
              for (final p in people)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: EmployeeAvatar(
                      initials: p.initials, url: p.avatarUrl, radius: 18,),
                  title: Text(p.fullName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,),
                  subtitle: Text(
                    p.jobTitle?.isNotEmpty == true ? p.jobTitle! : p.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.go('/employees/${p.id}', extra: p),
                ),
          ],
        ),
      ),
    );
  }
}

class _RelationsLoading extends StatelessWidget {
  const _RelationsLoading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
}
