import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';

/// Phase 1 placeholder home. It exists to prove the full auth pipeline works:
/// profile load, role resolution, line-manager flags, and effective
/// permissions (role defaults + per-user overrides). The real dashboard
/// arrives in Phase 2.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final perms = ref.watch(permissionsControllerProvider);
    final profile = auth.profile;

    final granted = perms.permissions.entries
        .where((e) => e.value)
        .map((e) => kPermissionLabels[e.key] ?? e.key.key)
        .toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus HRM'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(profile?.initials ?? '?'),
              ),
              title: Text(
                profile?.fullName.isNotEmpty == true
                    ? profile!.fullName
                    : (profile?.email ?? 'User'),
              ),
              subtitle: Text(profile?.email ?? ''),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Session',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _kv('Role', auth.role?.name ?? '—'),
                  _kv('Is manager', '${auth.isManager}'),
                  _kv('Is line manager', '${auth.isLineManager}'),
                  _kv('Can create employee', '${auth.canCreateEmployee}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Effective permissions',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (perms.loading)
                        const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!perms.loading && granted.isEmpty)
                    const Text('No permissions granted.'),
                  ...granted.map(
                    (label) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.check, size: 16, color: Color(0xFF16A34A)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(label)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Phase 1 complete — full dashboard arrives in Phase 2.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 170, child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
