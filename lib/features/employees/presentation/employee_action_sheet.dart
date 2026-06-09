import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_controller.dart';
import '../data/employee.dart';
import '../data/employees_providers.dart';
import '../data/team_models.dart';
import 'employee_forms.dart';
import 'employee_profile_dialog.dart';
import 'leave_summary_sheet.dart';
import 'widgets/employee_avatar.dart';
import 'widgets/team_list.dart';

/// Action popup shown when an employee row is tapped (parity with the web
/// "Action Popup Overlay"): View Profile (everyone) + Edit / Leave /
/// Deactivate-Reactivate (managers) + Reports To + their Team.
Future<void> showEmployeeActions(BuildContext context, WidgetRef ref, EmployeeDirectoryItem e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ActionSheet(employee: e),
  );
}

class _ActionSheet extends ConsumerStatefulWidget {
  const _ActionSheet({required this.employee});
  final EmployeeDirectoryItem employee;
  @override
  ConsumerState<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends ConsumerState<_ActionSheet> {
  List<TeamMember> _team = [];
  Set<String> _managerIds = {};
  List<ManagerRef> _reportsTo = [];
  bool _loadingTeam = true;
  bool _loadingManagers = true;

  bool get _canManage => ref.read(authControllerProvider).isManager;

  @override
  void initState() {
    super.initState();
    if (_canManage) {
      _loadTeam();
      _loadReportsTo();
    } else {
      _loadingTeam = false;
      _loadingManagers = false;
    }
  }

  Future<void> _loadTeam() async {
    final repo = ref.read(employeesRepositoryProvider);
    try {
      final team = await repo.fetchCombinedTeam(widget.employee.id);
      final mgrs = await repo.detectManagers(team.map((m) => m.id).toList());
      if (mounted) {
        setState(() {
        _team = team;
        _managerIds = mgrs;
        _loadingTeam = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTeam = false);
    }
  }

  Future<void> _loadReportsTo() async {
    try {
      final mgrs = await ref.read(employeesRepositoryProvider).managersOf(widget.employee.id);
      if (mounted) {
        setState(() {
        _reportsTo = mgrs;
        _loadingManagers = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingManagers = false);
    }
  }

  Future<void> _deactivate() async {
    final e = widget.employee;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DeactivateDialog(name: e.fullName),
    );
    if (ok != true) return;
    try {
      await ref.read(employeesRepositoryProvider).deactivate(e.id, e.email);
      ref.invalidate(employeesListProvider);
      ref.invalidate(employeeByIdProvider(e.id));
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text('${e.fullName} has been deactivated')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $err')));
    }
  }

  Future<void> _reactivate() async {
    final e = widget.employee;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(employeesRepositoryProvider).reactivate(e.id, e.email);
      ref.invalidate(employeesListProvider);
      ref.invalidate(employeeByIdProvider(e.id));
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text('${e.fullName} has been reactivated')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $err')));
    }
  }

  Future<void> _addToTeam() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddToTeamSheet(managerId: widget.employee.id, managerName: widget.employee.firstName),
    );
    if (added == true) {
      ref.invalidate(employeesListProvider);
      _loadTeam();
    }
  }

  Future<void> _removeMember(TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from team?'),
        content: Text('${m.fullName} will be removed from ${widget.employee.firstName}\'s team.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(employeesRepositoryProvider).removeFromTeam(widget.employee.id, m.id);
      _loadTeam();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.employee;
    final isActive = e.displayStatus != 'inactive';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // Header
          Row(children: [
            EmployeeAvatar(initials: e.initials, url: e.avatarUrl, radius: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.fullName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(e.jobTitle?.isNotEmpty == true ? e.jobTitle! : 'Employee',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                ],
              ),
            ),
          ],),
          const SizedBox(height: 16),
          // Action grid
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            final actions = <Widget>[
              _actionBtn(context, Icons.person_outline, 'View Profile', () {
                showEmployeeProfile(context, ref, e);
              }, w,),
              if (_canManage) ...[
                _actionBtn(context, Icons.edit_outlined, 'Edit Details', () async {
                  final nav = Navigator.of(context);
                  final changed = await showEditEmployeeForm(context, ref, e);
                  if (changed == true && mounted) nav.pop();
                }, w,),
                _actionBtn(context, Icons.calendar_month_outlined, 'Leave', () {
                  showLeaveSummary(context, ref, e);
                }, w,),
                if (isActive)
                  _actionBtn(context, Icons.person_off_outlined, 'Deactivate', _deactivate, w, danger: true)
                else
                  _actionBtn(context, Icons.how_to_reg_outlined, 'Reactivate', _reactivate, w, success: true),
              ],
            ];
            return Wrap(spacing: 10, runSpacing: 10, children: actions);
          },),

          // Reports To
          if (_canManage) ...[
            const Divider(height: 28),
            Row(children: [
              Icon(Icons.workspace_premium_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('${e.firstName} Reports To', style: theme.textTheme.titleSmall),
            ],),
            const SizedBox(height: 8),
            if (_loadingManagers)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else if (_reportsTo.isEmpty)
              Text('Not assigned to any manager yet.', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant))
            else
              ..._reportsTo.map((mgr) => _managerCard(context, mgr)),

            // Team
            const Divider(height: 28),
            Row(children: [
              Icon(Icons.groups_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(child: Text("${e.firstName}'s Team (${_team.length})", style: theme.textTheme.titleSmall)),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('Add'),
                onPressed: _addToTeam,
              ),
            ],),
            const SizedBox(height: 8),
            if (_loadingTeam)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else if (_team.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Icon(Icons.groups_outlined, size: 32, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 6),
                  Text('No team members assigned', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text('Tap "Add" to assign employees.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],),
              )
            else
              TeamList(
                members: _team,
                managerIds: _managerIds,
                onDrill: (m) => showSubTeam(context, ref, m),
                onRemove: _removeMember,
              ),
          ],
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, String label, VoidCallback onTap, double width, {bool danger = false, bool success = false}) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : (success ? Colors.green.shade700 : null);
    return SizedBox(
      width: width,
      height: 84,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: color, side: color != null ? BorderSide(color: color.withValues(alpha: 0.4)) : null),
        onPressed: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 24),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],),
      ),
    );
  }

  Widget _managerCard(BuildContext context, ManagerRef mgr) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(mgr.initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(mgr.fullName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Icon(Icons.workspace_premium, size: 13, color: theme.colorScheme.primary),
              ],),
              Text('${mgr.jobTitle ?? 'Manager'}${mgr.department != null ? ' · ${mgr.department}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis,),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.mail_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
          onPressed: () => launchUrl(Uri.parse('mailto:${mgr.email}')),
        ),
      ],),
    );
  }
}

/// Rich deactivate confirmation (parity with DeactivateDialog).
class _DeactivateDialog extends StatelessWidget {
  const _DeactivateDialog({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = theme.colorScheme.error;
    return AlertDialog(
      title: Row(children: [
        CircleAvatar(backgroundColor: err.withValues(alpha: 0.12), child: Icon(Icons.gpp_bad_outlined, color: err)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Deactivate Employee')),
      ],),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Are you sure you want to deactivate '),
            TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const TextSpan(text: '?'),
          ],),),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: err.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: err.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: err),
                const SizedBox(width: 6),
                Text('This action will:', style: TextStyle(color: err, fontWeight: FontWeight.w600, fontSize: 13)),
              ],),
              const SizedBox(height: 6),
              ...['Immediately revoke their system access', 'Block them from logging in or signing up', 'Set their status to inactive'].map(
                (t) => Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text('•  $t', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            ],),
          ),
          const SizedBox(height: 10),
          Text('To restore access, an Admin or Executive must reactivate the employee from the Employees page.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: err),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes, Deactivate'),
        ),
      ],
    );
  }
}

/// Multi-select picker of unassigned employees → add_team_member RPC.
class _AddToTeamSheet extends ConsumerStatefulWidget {
  const _AddToTeamSheet({required this.managerId, required this.managerName});
  final String managerId;
  final String managerName;
  @override
  ConsumerState<_AddToTeamSheet> createState() => _AddToTeamSheetState();
}

class _AddToTeamSheetState extends ConsumerState<_AddToTeamSheet> {
  List<TeamMember> _available = [];
  final Set<String> _selected = {};
  String _search = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _available = await ref.read(employeesRepositoryProvider).availableForTeam(widget.managerId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _assign() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final repo = ref.read(employeesRepositoryProvider);
    for (final id in _selected) {
      try {
        await repo.addTeamMember(widget.managerId, id);
      } catch (_) {}
    }
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _available.where((e) => e.fullName.toLowerCase().contains(_search.toLowerCase())).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Add to ${widget.managerName}'s Team", style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search employees…'),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(child: Text(_search.isEmpty ? 'No unassigned employees available' : 'No matching employees', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            final sel = _selected.contains(e.id);
                            return CheckboxListTile(
                              value: sel,
                              onChanged: (_) => setState(() => sel ? _selected.remove(e.id) : _selected.add(e.id)),
                              title: Text(e.fullName),
                              subtitle: Text('${e.jobTitle ?? '-'}${e.department != null ? ' · ${e.department}' : ''}', overflow: TextOverflow.ellipsis),
                              secondary: CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Text(e.initials, style: TextStyle(fontSize: 11, color: theme.colorScheme.onPrimaryContainer)),
                              ),
                              dense: true,
                            );
                          },
                        ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty || _saving ? null : _assign,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Add to Team (${_selected.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
