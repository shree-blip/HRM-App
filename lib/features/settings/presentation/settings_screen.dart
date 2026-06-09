import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/shell/app_drawer.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/data/profile_providers.dart';
import '../data/settings_providers.dart';

/// Settings (parity with hrm-update): Profile / Notifications / Security /
/// Company tabs. All authenticated users (no permission gate). No schema change.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.person_outline), text: 'Profile'),
              Tab(icon: Icon(Icons.notifications_none), text: 'Notifications'),
              Tab(icon: Icon(Icons.shield_outlined), text: 'Security'),
              Tab(icon: Icon(Icons.apartment_outlined), text: 'Company'),
            ],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/settings'),
        body: const TabBarView(
          children: [_ProfileTab(), _NotificationsTab(), _SecurityTab(), _CompanyTab()],
        ),
      ),
    );
  }
}

// ════════════════ Profile ════════════════
class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab();
  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  bool _init = false;
  bool _saving = false;
  bool _uploading = false;
  Uint8List? _preview;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _seed(ProfileData p) {
    if (_init) return;
    _init = true;
    _first.text = p.firstName ?? '';
    _last.text = p.lastName ?? '';
    _phone.text = p.phone ?? '';
  }

  Future<void> _pickPhoto(ProfileData p) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final ext = picked.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
      messenger.showSnackBar(const SnackBar(content: Text('Please pick a JPG, PNG, WebP, or GIF image.')));
      return;
    }
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      messenger.showSnackBar(const SnackBar(content: Text('Image must be under 5MB.')));
      return;
    }
    setState(() {
      _preview = bytes;
      _uploading = true;
    });
    try {
      await ref.read(settingsRepositoryProvider).uploadAvatar(bytes, ext == 'jpeg' ? 'jpg' : ext);
      ref.invalidate(profileProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Photo updated.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
        _uploading = false;
        _preview = null;
      });
      }
    }
  }

  Future<void> _removePhoto(ProfileData p) async {
    setState(() => _uploading = true);
    try {
      await ref.read(settingsRepositoryProvider).removeAvatar(p.avatarPath);
      ref.invalidate(profileProvider);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(settingsRepositoryProvider).updateProfile(firstName: _first.text, lastName: _last.text, phone: _phone.text);
      ref.invalidate(profileProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(profileProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load.\n$e')),
      data: (p) {
        if (p == null) return const Center(child: Text('Not signed in.'));
        _seed(p);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Profile Information', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: _preview != null
                      ? MemoryImage(_preview!)
                      : (p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null) as ImageProvider?,
                  child: _uploading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : (_preview == null && p.avatarUrl == null
                          ? Text(p.initials, style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer))
                          : null),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.upload, size: 16),
                          label: const Text('Change Photo'),
                          onPressed: _uploading ? null : () => _pickPhoto(p),
                        ),
                        if (p.avatarUrl != null)
                          IconButton(
                            icon: Icon(Icons.close, color: theme.colorScheme.error),
                            onPressed: _uploading ? null : () => _removePhoto(p),
                          ),
                      ],),
                      Text('JPG, PNG, WebP or GIF. Max 5MB.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Row(children: [
              Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'First Name'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Last Name'))),
            ],),
            const SizedBox(height: 12),
            TextField(controller: TextEditingController(text: p.email ?? ''), enabled: false, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextField(controller: TextEditingController(text: p.jobTitle ?? 'Employee'), enabled: false, decoration: const InputDecoration(labelText: 'Role')),
            const SizedBox(height: 12),
            TextField(controller: TextEditingController(text: p.department ?? 'General'), enabled: false, decoration: const InputDecoration(labelText: 'Department')),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ════════════════ Notifications ════════════════
class _NotificationsTab extends ConsumerWidget {
  const _NotificationsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userPreferencesProvider);
    final activity = ref.watch(activityAlertsProvider);

    Future<void> toggle(String key, bool value) async {
      await ref.read(settingsRepositoryProvider).updatePreference(key, value);
      ref.invalidate(userPreferencesProvider);
    }

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load.\n$e')),
      data: (p) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Notification Preferences', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _row('Leave Requests', 'Get notified when team members request leave', p.leave, (v) => toggle('leave_notifications', v)),
          _row('Task Assignments', 'Receive alerts for new task assignments', p.task, (v) => toggle('task_notifications', v)),
          _row('Payroll Reminders', 'Get reminded before payroll deadlines', p.payroll, (v) => toggle('payroll_notifications', v)),
          _row('Performance Reviews', 'Notifications for review cycles', p.performance, (v) => toggle('performance_notifications', v)),
          _row('Email Digest', 'Receive daily summary of activities', p.emailDigest, (v) => toggle('email_digest', v)),
          _row('Global Activity Alerts', 'Real-time alerts when teammates clock in, take breaks, or change status',
              activity, (v) => ref.read(activityAlertsProvider.notifier).state = v,),
        ],
      ),
    );
  }

  Widget _row(String title, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        value: value,
        onChanged: onChanged,
      );
}

// ════════════════ Security ════════════════
class _SecurityTab extends ConsumerStatefulWidget {
  const _SecurityTab();
  @override
  ConsumerState<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends ConsumerState<_SecurityTab> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCur = false, _showNew = false, _showConf = false, _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (_new.text != _confirm.text) {
      setState(() => _error = "New password and confirmation must match.");
      return;
    }
    if (_new.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(settingsRepositoryProvider).changePassword(_new.text);
      _current.clear();
      _new.clear();
      _confirm.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Password updated.')));
    } catch (e) {
      setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Security Settings', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Two-Factor Authentication', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Add an extra layer of security'),
              ],),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFF16A34A)), borderRadius: BorderRadius.circular(20)),
              child: const Text('Enabled', style: TextStyle(color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],),
        ),
        const SizedBox(height: 16),
        _pwd('Current Password', _current, _showCur, () => setState(() => _showCur = !_showCur)),
        const SizedBox(height: 12),
        _pwd('New Password', _new, _showNew, () => setState(() => _showNew = !_showNew)),
        const SizedBox(height: 12),
        _pwd('Confirm New Password', _confirm, _showConf, () => setState(() => _showConf = !_showConf)),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving || _new.text.isEmpty ? null : _update,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Update Password'),
          ),
        ),
      ],
    );
  }

  Widget _pwd(String label, TextEditingController c, bool show, VoidCallback toggle) => TextField(
        controller: c,
        obscureText: !show,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(icon: Icon(show ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: toggle),
        ),
      );
}

// ════════════════ Company (local-only, like web) ════════════════
class _CompanyTab extends StatefulWidget {
  const _CompanyTab();
  @override
  State<_CompanyTab> createState() => _CompanyTabState();
}

class _CompanyTabState extends State<_CompanyTab> {
  final _name = TextEditingController(text: 'Focus Your Finance');
  final _tz = TextEditingController(text: 'America/New_York (EST)');
  final _fiscal = TextEditingController(text: 'January 1');
  final _pay = TextEditingController(text: 'Semi-Monthly');
  bool _changed = false;

  @override
  void dispose() {
    _name.dispose();
    _tz.dispose();
    _fiscal.dispose();
    _pay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void onChange(_) => setState(() => _changed = true);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Company Settings', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: _name, onChanged: onChange, decoration: const InputDecoration(labelText: 'Company Name')),
        const SizedBox(height: 12),
        TextField(controller: _tz, onChanged: onChange, decoration: const InputDecoration(labelText: 'Timezone')),
        const SizedBox(height: 12),
        TextField(controller: _fiscal, onChanged: onChange, decoration: const InputDecoration(labelText: 'Fiscal Year Start')),
        const SizedBox(height: 12),
        TextField(controller: _pay, onChanged: onChange, decoration: const InputDecoration(labelText: 'Pay Frequency')),
        const Divider(height: 28),
        Text('Regional Settings', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _region(theme, '🇺🇸 US Operations', '32 employees • FLSA Compliant'),
        const SizedBox(height: 8),
        _region(theme, '🇳🇵 Nepal Operations', '16 employees • Nepal Labor Act'),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: !_changed
                ? null
                : () {
                    setState(() => _changed = false);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Company settings saved.')));
                  },
            child: const Text('Save Settings'),
          ),
        ),
      ],
    );
  }

  Widget _region(ThemeData theme, String title, String sub) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],),
      );
}
