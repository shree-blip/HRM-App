import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/employee.dart';
import '../data/employees_providers.dart';
import '../data/team_models.dart';
import 'widgets/employee_avatar.dart';
import 'widgets/team_list.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String? _formatMilestone(String? value) {
  if (value == null || value.isEmpty) return null;
  final d = DateTime.tryParse(value);
  if (d == null) return null;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// View Profile (parity with EmployeeProfileDialog): Contact / Work /
/// Milestones / Team Members table with drill-down.
Future<void> showEmployeeProfile(BuildContext context, WidgetRef ref, EmployeeDirectoryItem e) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ProfileSheet(employee: e),
  );
}

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({required this.employee});
  final EmployeeDirectoryItem employee;
  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  String? _phone;
  EmployeeMilestones _milestones = const EmployeeMilestones();
  List<TeamMember> _team = [];
  Set<String> _managerIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(employeesRepositoryProvider);
    final e = widget.employee;
    try {
      final full = await repo.fullById(e.id);
      _phone = full?.phone;
    } catch (_) {}
    try {
      _milestones = await repo.milestones(profileId: e.profileId);
    } catch (_) {}
    try {
      _team = await repo.fetchCombinedTeam(e.id);
      _managerIds = await repo.detectManagers(_team.map((m) => m.id).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.employee;
    final dob = _formatMilestone(_milestones.dob);
    final joining = _formatMilestone(_milestones.joining);
    final years = _milestones.years(DateTime.now());
    final flag = e.location == 'US' ? '🇺🇸' : '🇳🇵';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Employee Profile', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          // Header
          Row(children: [
            EmployeeAvatar(initials: e.initials, url: e.avatarUrl, radius: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.fullName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(e.jobTitle?.isNotEmpty == true ? e.jobTitle! : 'Employee',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                  const SizedBox(height: 6),
                  statusChip(context, e.displayStatus),
                ],
              ),
            ),
          ],),
          const Divider(height: 28),
          // Contact
          Text('Contact Information', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _row(context, Icons.mail_outline, e.email, onTap: () => launchUrl(Uri.parse('mailto:${e.email}')), link: true),
          _row(context, Icons.phone_outlined, (_phone?.isNotEmpty == true) ? _phone! : 'Not provided'),
          _row(context, Icons.location_on_outlined, '$flag ${e.location ?? '-'}'),
          const Divider(height: 28),
          // Work
          Text('Work Information', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _row(context, Icons.apartment_outlined, e.department ?? '-'),
          _row(context, Icons.work_outline, e.jobTitle?.isNotEmpty == true ? e.jobTitle! : 'Employee'),
          // Milestones
          if (dob != null || joining != null) ...[
            const Divider(height: 28),
            Text('Milestones', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (dob != null) _row(context, Icons.cake_outlined, 'Birthday: $dob'),
            if (joining != null)
              _row(context, Icons.favorite_border, 'Work Anniversary: $joining${years != null ? ' · $years yr${years != 1 ? 's' : ''}' : ''}'),
          ],
          // Team
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else if (_team.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.groups_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('Team Members (${_team.length})', style: theme.textTheme.titleSmall),
            ],),
            const SizedBox(height: 8),
            TeamList(
              members: _team,
              managerIds: _managerIds,
              onDrill: (m) => showSubTeam(context, ref, m),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text, {VoidCallback? onTap, bool link = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: link ? theme.colorScheme.primary : null,
                  decoration: link ? TextDecoration.underline : null,
                ),),
          ),
        ),
      ],),
    );
  }
}
