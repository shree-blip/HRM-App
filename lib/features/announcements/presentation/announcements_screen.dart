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
        body: TabBarView(
          children: [
            _List(provider: activeAnnouncementsProvider, canManage: canManage, isHistory: false),
            _List(provider: announcementHistoryProvider, canManage: canManage, isHistory: true),
          ],
        ),
      ),
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
  bool _busy = false;
  String? _error;

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
          DropdownButtonFormField<Duration?>(
            initialValue: _duration,
            decoration: const InputDecoration(labelText: 'Expires'),
            items: [for (final d in kAnnouncementDurations) DropdownMenuItem(value: d.$2, child: Text(d.$1))],
            onChanged: (v) => setState(() => _duration = v),
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
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await widget.ref.read(announcementsRepositoryProvider).create(
            title: _title.text,
            content: _content.text,
            type: _type,
            isPinned: _pinned,
            expiresAt: _duration == null ? null : DateTime.now().toUtc().add(_duration!),
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
