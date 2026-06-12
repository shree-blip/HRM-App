import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/announcement_models.dart';
import '../data/announcements_providers.dart';

/// Announcements (Phase 11): Live + History tabs. Create / soft-delete /
/// restore / permanent-delete. No edit, no targeting (matches the web).
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = canManageAnnouncements(ref);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Announcements'),
          bottom: const TabBar(tabs: [Tab(text: 'Live'), Tab(text: 'History')]),
        ),
        drawer: const AppDrawer(currentRoute: '/announcements'),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: () => _showForm(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              )
            : null,
        body: Column(
          children: [
            const _StatsCards(),
            Expanded(
              child: TabBarView(
                children: [
                  _List(provider: activeAnnouncementsProvider, canManage: canManage, isHistory: false),
                  _List(provider: announcementHistoryProvider, canManage: canManage, isHistory: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live / Pinned / Today / History counts (web Announcements stats cards).
class _StatsCards extends ConsumerWidget {
  const _StatsCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(activeAnnouncementsProvider).valueOrNull ?? const [];
    final history = ref.watch(announcementHistoryProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final today = live.where((a) {
      final c = a.createdAt?.toLocal();
      return c != null && c.year == now.year && c.month == now.month && c.day == now.day;
    }).length;
    final pinned = live.where((a) => a.isPinned).length;

    Widget card(String label, int value, IconData icon, Color color) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text('$value',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: color,),),
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),),
            ],),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(children: [
        card('Live', live.length, Icons.campaign_outlined, const Color(0xFF2563EB)),
        card('Pinned', pinned, Icons.push_pin_outlined, const Color(0xFFD97706)),
        card('Today', today, Icons.today_outlined, const Color(0xFF16A34A)),
        card('History', history.length, Icons.history, const Color(0xFF6B7280)),
      ],),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.provider, required this.canManage, required this.isHistory});
  final AutoDisposeFutureProvider<List<Announcement>> provider;
  final bool canManage;
  final bool isHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(provider);
        await ref.read(provider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
        data: (items) => items.isEmpty
            ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(isHistory ? 'No history.' : 'No announcements.')))])
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                children: [for (final a in items) _Card(a: a, canManage: canManage, isHistory: isHistory)],
              ),
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.a, required this.canManage, required this.isHistory});
  final Announcement a;
  final bool canManage;
  final bool isHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (bg, fg) = announcementTypeColors(a.type);
    void refresh() {
      ref.invalidate(activeAnnouncementsProvider);
      ref.invalidate(announcementHistoryProvider);
    }

    Future<void> run(Future<void> Function() f) async {
      final m = ScaffoldMessenger.of(context);
      try {
        await f();
        refresh();
      } catch (e) {
        m.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }

    final repo = ref.read(announcementsRepositoryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (a.isPinned) Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.push_pin, size: 16, color: theme.colorScheme.primary),
                ),
                Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                  child: Text(a.type, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(a.content, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Wrap(spacing: 12, runSpacing: 2, children: [
              _meta(theme, Icons.person_outline, a.publisherName ?? 'System'),
              if (a.expiresAt != null)
                _meta(theme, Icons.schedule, '${a.isExpired ? 'Expired' : 'Ends'} ${_fmt(a.expiresAt!)}'),
              if (isHistory && !a.isActive) _meta(theme, Icons.cancel_outlined, 'Removed'),
            ],),
            if (canManage) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isHistory)
                    TextButton.icon(
                      icon: const Icon(Icons.archive_outlined, size: 16),
                      label: const Text('Remove'),
                      onPressed: () => run(() => repo.softDelete(a.id)),
                    )
                  else ...[
                    TextButton.icon(
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('Restore'),
                      onPressed: () => run(() => repo.restore(a.id)),
                    ),
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline, size: 16, color: theme.colorScheme.error),
                      label: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete permanently?'),
                            content: const Text('This cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) run(() => repo.permanentDelete(a.id));
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  static String _fmt(DateTime utc) {
    final d = utc.add(const Duration(hours: 5, minutes: 45));
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

void _showForm(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _Form(ref: ref),
    ),
  );
}

class _Form extends StatefulWidget {
  const _Form({required this.ref});
  final WidgetRef ref;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String _type = 'info';
  bool _pinned = false;
  Duration? _duration;
  bool _customExpiryMode = false;
  DateTime? _customExpiry; // local time, like the web datetime-local input
  bool _busy = false;
  String? _error;

  Future<void> _pickCustomExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _customExpiry ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_customExpiry ?? now),
    );
    if (time == null) return;
    setState(() => _customExpiry =
        DateTime(date.year, date.month, date.day, time.hour, time.minute),);
  }

  String _fmtCustom(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New announcement', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title *')),
          const SizedBox(height: 12),
          TextField(controller: _content, maxLines: 4, decoration: const InputDecoration(labelText: 'Content *')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in kAnnouncementTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setState(() => _type = v ?? 'info'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _customExpiryMode
                ? kAnnouncementDurations.length
                : kAnnouncementDurations
                    .indexWhere((d) => d.$2 == _duration)
                    .clamp(0, kAnnouncementDurations.length - 1),
            decoration: const InputDecoration(labelText: 'Expires'),
            items: [
              for (var i = 0; i < kAnnouncementDurations.length; i++)
                DropdownMenuItem(value: i, child: Text(kAnnouncementDurations[i].$1)),
              DropdownMenuItem(
                  value: kAnnouncementDurations.length,
                  child: const Text('Custom date/time'),),
            ],
            onChanged: (v) => setState(() {
              if (v == null) return;
              if (v == kAnnouncementDurations.length) {
                _customExpiryMode = true;
              } else {
                _customExpiryMode = false;
                _customExpiry = null;
                _duration = kAnnouncementDurations[v].$2;
              }
            }),
          ),
          if (_customExpiryMode)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event, size: 16),
                label: Text(_customExpiry == null
                    ? 'Pick expiry date & time'
                    : 'Expires ${_fmtCustom(_customExpiry!)}',),
                onPressed: _pickCustomExpiry,
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pin to top'),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Post announcement'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      setState(() => _error = 'Title and content are required.');
      return;
    }
    // Custom expiry validation — web: required + must be in the future.
    if (_customExpiryMode) {
      if (_customExpiry == null) {
        setState(() => _error = 'Please choose an expiry date/time.');
        return;
      }
      if (!_customExpiry!.isAfter(DateTime.now())) {
        setState(() => _error = 'Expiry time must be in the future.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final expiresAt = _customExpiryMode
          ? _customExpiry!.toUtc()
          : (_duration == null ? null : DateTime.now().toUtc().add(_duration!));
      await widget.ref.read(announcementsRepositoryProvider).create(
            title: _title.text,
            content: _content.text,
            type: _type,
            isPinned: _pinned,
            expiresAt: expiresAt,
          );
      widget.ref.invalidate(activeAnnouncementsProvider);
      widget.ref.invalidate(announcementHistoryProvider);
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
