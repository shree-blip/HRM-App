import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/profile_models.dart';
import '../data/profile_providers.dart';

/// Profile (Phase 12): self profile from `profiles`. View + edit personal/
/// contact/milestone fields; change password. Job info is read-only (HR).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    final auth = ref.watch(authControllerProvider);
    final roleLabel = auth.isAdmin
        ? 'Admin'
        : auth.isVp
            ? 'Executive'
            : auth.isSupervisor
                ? 'Supervisor'
                : auth.isManager
                    ? 'Manager'
                    : auth.isLineManager
                        ? 'Line Manager'
                        : 'Employee';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Change password',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => _showChangePassword(context, ref),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/profile'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load profile.\n$e', textAlign: TextAlign.center)),
        data: (p) {
          if (p == null) return const Center(child: Text('Not signed in.'));
          final theme = Theme.of(context);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(profileProvider);
              await ref.read(profileProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
                        child: p.avatarUrl == null
                            ? Text(p.initials, style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer))
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Text(p.fullName.isEmpty ? 'Unnamed' : p.fullName,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(20)),
                          child: Text(roleLabel, style: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        if (p.jobTitle != null && p.jobTitle!.isNotEmpty)
                          Text(p.jobTitle!, style: theme.textTheme.bodyMedium),
                      ],),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit profile'),
                        onPressed: () => _showEdit(context, ref, p),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(theme, 'Contact information', [
                  _row(theme, Icons.email_outlined, 'Email', p.email, readOnly: true),
                  _row(theme, Icons.phone_outlined, 'Phone', p.phone),
                  _row(theme, Icons.location_on_outlined, 'Location', p.location),
                ]),
                _section(theme, 'Employment information', [
                  _row(theme, Icons.badge_outlined, 'Job title', p.jobTitle, readOnly: true),
                  _row(theme, Icons.apartment_outlined, 'Department', p.department, readOnly: true),
                  _row(theme, Icons.verified_outlined, 'Status', p.status, readOnly: true),
                ]),
                _section(theme, 'Milestones', [
                  _row(theme, Icons.cake_outlined, 'Date of birth', p.dateOfBirth),
                  _row(theme, Icons.event_available_outlined, 'Joining date', p.joiningDate),
                ]),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> rows) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...rows,
            ],
          ),
        ),
      );

  Widget _row(ThemeData theme, IconData icon, String label, String? value, {bool readOnly = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    (value == null || value.isEmpty) ? '—' : value,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (readOnly) Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      );
}

// ── Edit profile ─────────────────────────────────────────
void _showEdit(BuildContext context, WidgetRef ref, ProfileData p) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _EditForm(ref: ref, profile: p),
    ),
  );
}

class _EditForm extends StatefulWidget {
  const _EditForm({required this.ref, required this.profile});
  final WidgetRef ref;
  final ProfileData profile;
  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _phone;
  late final TextEditingController _location;
  String? _dob;
  String? _joining;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _first = TextEditingController(text: p.firstName ?? '');
    _last = TextEditingController(text: p.lastName ?? '');
    _phone = TextEditingController(text: p.phone ?? '');
    _location = TextEditingController(text: p.location ?? '');
    _dob = p.dateOfBirth;
    _joining = p.joiningDate;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool dob) async {
    final cur = (dob ? _dob : _joining);
    final init = cur != null ? DateTime.tryParse(cur) ?? DateTime(2000) : DateTime(2000);
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(1950), lastDate: DateTime(DateTime.now().year + 1));
    if (d != null) {
      final s = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      setState(() => dob ? _dob = s : _joining = s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit profile', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'First name *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Last name *'))),
          ],),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: InkWell(
              onTap: () => _pickDate(true),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Date of birth'), child: Text(_dob ?? 'Not set')),
            ),),
            const SizedBox(width: 12),
            Expanded(child: InkWell(
              onTap: () => _pickDate(false),
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Joining date'), child: Text(_joining ?? 'Not set')),
            ),),
          ],),
          if (widget.profile.avatarUrl != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove photo'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await widget.ref.read(profileRepositoryProvider).removeAvatar(widget.profile.avatarPath);
                  widget.ref.invalidate(profileProvider);
                  if (mounted) nav.pop();
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
          const SizedBox(height: 8),
          Text('Job title, department, status and email are managed by HR.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = 'First and last name are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await widget.ref.read(profileRepositoryProvider).update(
            firstName: _first.text,
            lastName: _last.text,
            phone: _phone.text,
            location: _location.text,
            dateOfBirth: _dob,
            joiningDate: _joining,
          );
      widget.ref.invalidate(profileProvider);
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
      }
    }
  }
}

// ── Change password ──────────────────────────────────────
void _showChangePassword(BuildContext context, WidgetRef ref) {
  final pwd = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  var busy = false;
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: pwd, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
              const SizedBox(height: 8),
              TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password')),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (pwd.text.length < 6) {
                        setLocal(() => error = 'Password must be at least 6 characters.');
                        return;
                      }
                      if (pwd.text != confirm.text) {
                        setLocal(() => error = 'Passwords do not match.');
                        return;
                      }
                      setLocal(() => busy = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(ctx);
                      try {
                        await ref.read(profileRepositoryProvider).changePassword(pwd.text);
                        nav.pop();
                        messenger.showSnackBar(const SnackBar(content: Text('Password updated.')));
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          error = 'Failed: $e';
                        });
                      }
                    },
              child: const Text('Update'),
            ),
          ],
        );
      },
    ),
  );
}
