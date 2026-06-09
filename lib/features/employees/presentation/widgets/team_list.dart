import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/employees_providers.dart';
import '../../data/team_models.dart';

/// Status pill color (active=green, probation=amber, inactive=red) — mirrors
/// the web badge variants.
({Color fg, Color bg}) statusColors(BuildContext context, String status) {
  final s = status.toLowerCase();
  if (s == 'inactive') return (fg: Colors.red.shade700, bg: Colors.red.withValues(alpha: 0.10));
  if (s == 'probation') return (fg: Colors.orange.shade800, bg: Colors.orange.withValues(alpha: 0.12));
  return (fg: Colors.green.shade700, bg: Colors.green.withValues(alpha: 0.12));
}

Widget statusChip(BuildContext context, String status) {
  final c = statusColors(context, status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.fg.withValues(alpha: 0.4))),
    child: Text(status, style: TextStyle(color: c.fg, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

/// Renders a team as mobile-clean cards: avatar + name (+ "Team Lead" badge if
/// the member manages others), email, role, department + status, and a
/// drill-down chevron or remove button.
class TeamList extends StatelessWidget {
  const TeamList({
    super.key,
    required this.members,
    required this.managerIds,
    this.onDrill,
    this.onRemove,
  });

  final List<TeamMember> members;
  final Set<String> managerIds;
  final void Function(TeamMember)? onDrill;
  final void Function(TeamMember)? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final m in members)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: managerIds.contains(m.id) && onDrill != null ? () => onDrill!(m) : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(m.initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                              if (managerIds.contains(m.id)) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.groups, size: 11, color: theme.colorScheme.primary),
                                    const SizedBox(width: 2),
                                    Text('Team Lead', style: TextStyle(fontSize: 9, color: theme.colorScheme.primary)),
                                  ],),
                                ),
                              ],
                            ],
                          ),
                          Text(m.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(children: [
                            Text(m.jobTitle ?? '-', style: theme.textTheme.bodySmall),
                            const SizedBox(width: 8),
                            if (m.department != null && m.department!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                                child: Text(m.department!, style: theme.textTheme.bodySmall),
                              ),
                          ],),
                          const SizedBox(height: 4),
                          statusChip(context, m.displayStatus),
                        ],
                      ),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: 'Remove from team',
                        icon: Icon(Icons.person_remove_outlined, size: 18, color: theme.colorScheme.error),
                        onPressed: () => onRemove!(m),
                      )
                    else if (managerIds.contains(m.id) && onDrill != null)
                      Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Drill-down modal: shows a manager's sub-team with a breadcrumb stack; tapping
/// a sub-manager pushes deeper, back pops.
Future<void> showSubTeam(BuildContext context, WidgetRef ref, TeamMember root) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SubTeamSheet(root: root),
  );
}

class _SubTeamSheet extends ConsumerStatefulWidget {
  const _SubTeamSheet({required this.root});
  final TeamMember root;
  @override
  ConsumerState<_SubTeamSheet> createState() => _SubTeamSheetState();
}

class _SubTeamSheetState extends ConsumerState<_SubTeamSheet> {
  final List<TeamMember> _stack = [];
  List<TeamMember> _members = [];
  Set<String> _managerIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _stack.add(widget.root);
    _load(widget.root.id);
  }

  Future<void> _load(String id) async {
    setState(() => _loading = true);
    final repo = ref.read(employeesRepositoryProvider);
    try {
      final members = await repo.fetchCombinedTeam(id);
      final mgrs = await repo.detectManagers(members.map((m) => m.id).toList());
      if (mounted) {
        setState(() {
        _members = members;
        _managerIds = mgrs;
        _loading = false;
      });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
        _members = [];
        _loading = false;
      });
      }
    }
  }

  void _drill(TeamMember m) {
    setState(() => _stack.add(m));
    _load(m.id);
  }

  void _back() {
    if (_stack.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _stack.removeLast());
    _load(_stack.last.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _stack.last;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (_stack.length > 1)
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
              Icon(Icons.groups, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(child: Text("${current.fullName}'s Team", style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
            ],),
            if (_stack.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_stack.map((s) => s.fullName).join('  ›  '), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _members.isEmpty
                      ? Center(child: Text('No team members under ${current.fullName}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                      : ListView(
                          controller: scrollController,
                          children: [TeamList(members: _members, managerIds: _managerIds, onDrill: _drill)],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
