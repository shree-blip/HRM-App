import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../data/access_models.dart';
import '../data/access_providers.dart';

/// Access Control (parity with the web AccessControl page): User Roles,
/// Role Permissions matrix, Individual Permissions (3-state overrides + audit),
/// and a Security Monitor tab for flagged users. Gated by manage_access.
class AccessControlScreen extends ConsumerWidget {
  const AccessControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsControllerProvider);
    final canAccess = perms.has(Permission.manageAccess);
    final stillResolving = perms.loading && !canAccess;

    return Scaffold(
      appBar: AppBar(title: const Text('Access Control')),
      drawer: const AppDrawer(currentRoute: '/access-control'),
      body: stillResolving
          ? const Center(child: CircularProgressIndicator())
          : !canAccess
              ? const _NoAccess()
              : const _AccessTabs(),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Access Denied', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text("You don't have permission to access this page.",
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        ],),
      ),
    );
  }
}

class _AccessTabs extends ConsumerWidget {
  const _AccessTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessControllerProvider);
    if (state.loading) return const Center(child: CircularProgressIndicator());
    final showSecurity = state.isSecurityMonitor;

    return DefaultTabController(
      length: showSecurity ? 4 : 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabs: [
                const Tab(icon: Icon(Icons.group_outlined), text: 'User Roles'),
                const Tab(icon: Icon(Icons.lock_outline), text: 'Role Permissions'),
                const Tab(icon: Icon(Icons.person_outline), text: 'Individual'),
                if (showSecurity) const Tab(icon: Icon(Icons.warning_amber_outlined), text: 'Security'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _UserRolesTab(),
                const _RolePermissionsTab(),
                const _IndividualTab(),
                if (showSecurity) const _SecurityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════ Shared bits ════════════════
Widget _roleBadge(BuildContext context, String role) {
  final theme = Theme.of(context);
  Color c;
  switch (role) {
    case 'vp':
      c = theme.colorScheme.primary;
    case 'admin':
      c = theme.colorScheme.error;
    case 'supervisor':
      c = Colors.orange.shade700;
    case 'line_manager':
      c = Colors.blue.shade600;
    default:
      c = theme.colorScheme.onSurfaceVariant;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.5))),
    child: Text(roleLabel(role), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

Widget _userAvatar(BuildContext context, AccessUser u, {double radius = 18}) {
  final theme = Theme.of(context);
  if (u.isSpam) {
    return CircleAvatar(radius: radius, backgroundColor: theme.colorScheme.error.withValues(alpha: 0.15), child: Icon(Icons.warning_amber_rounded, size: radius, color: theme.colorScheme.error));
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: theme.colorScheme.primaryContainer,
    backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null,
    child: u.avatarUrl == null ? Text(u.initials, style: TextStyle(fontSize: radius * 0.6, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)) : null,
  );
}

// ════════════════ Tab 1: User Roles ════════════════
class _UserRolesTab extends ConsumerStatefulWidget {
  const _UserRolesTab();
  @override
  ConsumerState<_UserRolesTab> createState() => _UserRolesTabState();
}

class _UserRolesTabState extends ConsumerState<_UserRolesTab> {
  String _query = '';
  String? _saving;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accessControllerProvider);
    final theme = Theme.of(context);
    final users = _filter(state.users, _query, state.isSecurityMonitor);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search by name, email, or department'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final u = users[i];
              return Card(
                color: u.isSpam ? theme.colorScheme.error.withValues(alpha: 0.05) : null,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    _userAvatar(context, u),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.isSpam ? '⚠️ SPAM USER' : u.fullName,
                              style: TextStyle(fontWeight: FontWeight.w600, color: u.isSpam ? theme.colorScheme.error : null),),
                          Text(u.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${u.jobTitle ?? '-'}${u.department != null ? ' · ${u.department}' : ''}',
                              style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis,),
                          const SizedBox(height: 6),
                          Row(children: [
                            _roleBadge(context, u.role),
                            const SizedBox(width: 8),
                            _accountBadge(context, u),
                          ],),
                          const SizedBox(height: 8),
                          // Change role
                          if (u.hasAccount && !u.isSpam)
                            _saving == u.id
                                ? const SizedBox(height: 24, width: 24, child: Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2)))
                                : DropdownButton<String>(
                                    value: u.role,
                                    isDense: true,
                                    underline: const SizedBox.shrink(),
                                    items: [for (final r in kAccessRoles) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
                                    onChanged: (v) => v == null || v == u.role ? null : _changeRole(u, v),
                                  )
                          else
                            Text(u.hasAccount ? '' : 'No account — role applies after signup',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),),
                        ],
                      ),
                    ),
                  ],),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _accountBadge(BuildContext context, AccessUser u) {
    final theme = Theme.of(context);
    if (u.isSpam) {
      return _pill(context, 'SPAM', theme.colorScheme.error);
    }
    return _pill(context, u.hasAccount ? 'Active' : 'No Account', u.hasAccount ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant);
  }

  Future<void> _changeRole(AccessUser u, String role) async {
    setState(() => _saving = u.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(accessControllerProvider.notifier).changeRole(u, role);
      messenger.showSnackBar(SnackBar(content: Text('${u.fullName}\'s role changed to ${roleLabel(role)}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to update role: $e')));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }
}

Widget _pill(BuildContext context, String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );

List<AccessUser> _filter(List<AccessUser> users, String query, bool isSecurityMonitor) {
  final q = query.toLowerCase();
  return users.where((u) {
    if (u.isSpam && !isSecurityMonitor) return false;
    return q.isEmpty ||
        u.firstName.toLowerCase().contains(q) ||
        u.lastName.toLowerCase().contains(q) ||
        u.email.toLowerCase().contains(q) ||
        (u.department?.toLowerCase().contains(q) ?? false);
  }).toList();
}

// ════════════════ Tab 2: Role Permissions matrix (one role at a time) ════════════════
class _RolePermissionsTab extends ConsumerStatefulWidget {
  const _RolePermissionsTab();
  @override
  ConsumerState<_RolePermissionsTab> createState() => _RolePermissionsTabState();
}

class _RolePermissionsTabState extends ConsumerState<_RolePermissionsTab> {
  String _role = 'vp';

  bool get _isCEO => ref.read(authControllerProvider).isVp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(accessControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text('Role Permissions Matrix', style: theme.textTheme.titleMedium),
        Text('Configure default permissions for each role. VP permissions are protected.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        const SizedBox(height: 12),
        // Role selector
        Wrap(
          spacing: 8,
          children: [
            for (final r in kAccessRoles)
              ChoiceChip(
                label: Text(roleLabel(r)),
                selected: _role == r,
                onSelected: (_) => setState(() => _role = r),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in kPermissionCategories.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(entry.key.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
          ),
          for (final perm in entry.value) _permRow(context, state, perm),
        ],
      ],
    );
  }

  Widget _permRow(BuildContext context, AccessState state, Permission perm) {
    final role = _role;
    final enabled = state.roleHas(role, perm.key);
    final isProtected = ((role == 'vp' || role == 'admin') && perm == Permission.manageAccess) ||
        (perm == Permission.manageSalariesAll && role != 'vp' && role != 'admin');
    final lockedForNonCEO = perm == Permission.manageAccess && !_isCEO;
    final disabled = (isProtected && enabled) || lockedForNonCEO;
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(kPermissionLabels[perm] ?? perm.key),
      value: enabled,
      onChanged: disabled ? null : (_) => _toggle(role, perm, enabled),
    );
  }

  Future<void> _toggle(String role, Permission perm, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    if (perm == Permission.manageAccess && !_isCEO) {
      messenger.showSnackBar(const SnackBar(content: Text('Only the Executive can allow Manage Access Control.')));
      return;
    }
    if ((role == 'vp' || role == 'admin') && perm == Permission.manageAccess) {
      messenger.showSnackBar(const SnackBar(content: Text('VP and Admin must always have access control permission.')));
      return;
    }
    if (perm == Permission.manageSalariesAll && role != 'vp' && role != 'admin' && !enabled) {
      messenger.showSnackBar(const SnackBar(content: Text('Only VP/Admin can have salary management permission.')));
      return;
    }
    final ok = await ref.read(accessControllerProvider.notifier).toggleRolePermission(role, perm.key, enabled);
    messenger.showSnackBar(SnackBar(content: Text(ok
        ? '${kPermissionLabels[perm]} ${!enabled ? 'enabled' : 'disabled'} for ${roleLabel(role)}.'
        : 'Failed to update permission.',),),);
  }
}

// ════════════════ Tab 3: Individual Permissions ════════════════
class _IndividualTab extends ConsumerStatefulWidget {
  const _IndividualTab();
  @override
  ConsumerState<_IndividualTab> createState() => _IndividualTabState();
}

class _IndividualTabState extends ConsumerState<_IndividualTab> {
  String _query = '';
  AccessUser? _selected;

  bool get _isCEO => ref.read(authControllerProvider).isVp;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accessControllerProvider);
    if (_selected != null) {
      // Keep the selected reference fresh (role may have changed).
      final fresh = state.users.where((u) => u.id == _selected!.id).cast<AccessUser?>().firstWhere((u) => true, orElse: () => _selected);
      return _UserOverridesView(user: fresh!, isCEO: _isCEO, onBack: () => setState(() => _selected = null));
    }

    final theme = Theme.of(context);
    final users = _filter(state.users, _query, state.isSecurityMonitor).where((u) => u.hasAccount).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search users'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final u = users[i];
              final count = state.overrideCount(u.userId);
              return Card(
                child: ListTile(
                  onTap: () => setState(() => _selected = u),
                  leading: _userAvatar(context, u),
                  title: Text(u.fullName),
                  subtitle: Text(u.email, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (count > 0) ...[_pill(context, '$count custom', theme.colorScheme.secondary), const SizedBox(width: 6)],
                    const Icon(Icons.chevron_right),
                  ],),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserOverridesView extends ConsumerWidget {
  const _UserOverridesView({required this.user, required this.isCEO, required this.onBack});
  final AccessUser user;
  final bool isCEO;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(accessControllerProvider);
    final audit = ref.watch(auditLogsProvider(user.userId ?? ''));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.fullName, style: theme.textTheme.titleMedium),
              Row(children: [Text('Role: ', style: theme.textTheme.bodySmall), _roleBadge(context, user.role)]),
            ],),
          ),
        ],),
        Text('Toggle to create overrides. Tap again to cycle: Grant → Deny → Remove (role default).',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        if (!isCEO)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text('View only — only the Executive can modify individual permissions',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),),
            ],),
          ),
        const SizedBox(height: 8),
        for (final entry in kPermissionCategories.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(entry.key.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
          ),
          for (final perm in entry.value) _overrideRow(context, ref, state, perm),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.history, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Permission Change History', style: theme.textTheme.titleSmall),
        ],),
        const SizedBox(height: 8),
        audit.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          error: (_, __) => const Text('Could not load history.'),
          data: (logs) => logs.isEmpty
              ? Text('No permission changes recorded for this user.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Column(children: [for (final l in logs) _auditTile(context, state, l)]),
        ),
      ],
    );
  }

  Widget _overrideRow(BuildContext context, WidgetRef ref, AccessState state, Permission perm) {
    final theme = Theme.of(context);
    final roleDefault = state.roleHas(user.role, perm.key);
    final override = user.userId == null ? null : state.overrideFor(user.userId!, perm.key);
    final effective = override ?? roleDefault;
    final source = override != null ? 'Custom' : 'Role';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(kPermissionLabels[perm] ?? perm.key, style: const TextStyle(fontWeight: FontWeight.w500))),
            Switch(
              value: override == true,
              onChanged: !isCEO || user.userId == null
                  ? null
                  : (_) => ref.read(accessControllerProvider.notifier).cycleOverride(user.userId!, perm.key, override, roleDefault),
            ),
          ],),
          Row(children: [
            _miniTag(context, 'Default: ${roleDefault ? '✓' : '✗'}', theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            if (override != null) _miniTag(context, override ? 'Override ON' : 'Override OFF', override ? theme.colorScheme.primary : theme.colorScheme.error),
            const SizedBox(width: 6),
            _miniTag(context, effective ? '✓ Allowed' : '✗ Denied', effective ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            _miniTag(context, source, source == 'Custom' ? theme.colorScheme.secondary : theme.colorScheme.onSurfaceVariant),
          ],),
        ],
      ),
    );
  }

  Widget _auditTile(BuildContext context, AccessState state, AuditLogEntry l) {
    final theme = Theme.of(context);
    final perm = Permission.fromKey(l.permission);
    final by = state.users.where((u) => u.userId == l.changedBy).cast<AccessUser?>().firstWhere((u) => true, orElse: () => null);
    String fmt(bool? v) => v == null ? 'None' : (v ? 'ON' : 'OFF');
    final d = l.createdAt;
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(perm != null ? (kPermissionLabels[perm] ?? l.permission) : l.permission, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Row(children: [
            _miniTag(context, fmt(l.oldValue), theme.colorScheme.onSurfaceVariant),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('→')),
            _miniTag(context, fmt(l.newValue), l.newValue ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            const Spacer(),
            Text(dateStr, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],),
          Text('by ${by != null ? by.fullName : 'System'}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],),
      ),
    );
  }

  Widget _miniTag(BuildContext context, String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

// ════════════════ Tab 4: Security Monitor ════════════════
class _SecurityTab extends ConsumerWidget {
  const _SecurityTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spam = ref.watch(accessControllerProvider).users.where((u) => u.isSpam).toList();
    if (spam.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text('No flagged users found. System is secure.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: spam.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u = spam[i];
        return Card(
          color: theme.colorScheme.error.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              _userAvatar(context, u),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SPAM USER', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.error)),
                  Text(u.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text('Unauthorized signup — not in employee list', style: theme.textTheme.bodySmall),
                ],),
              ),
              _pill(context, 'Blocked', theme.colorScheme.error),
            ],),
          ),
        );
      },
    );
  }
}
