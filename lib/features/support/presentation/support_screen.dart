import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../data/asset_models.dart';
import '../data/asset_providers.dart';
import '../data/comment_models.dart';
import '../data/support_models.dart';
import '../data/support_providers.dart';
import 'comments_thread.dart';

/// Support, Bugs & Grievances (Phase 10). Single /support page with permission
/// -gated tabs: Bug Reports, Grievances, Asset Requests. (Support tickets do
/// not exist in the web app.)
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final perms = ref.watch(permissionsControllerProvider);
    final superUser = auth.isAdmin || auth.isVp;
    bool can(Permission p) => perms.has(p);

    final showBugs = superUser || can(Permission.viewBugReports) || can(Permission.submitBugReports) || can(Permission.manageSupport);
    final showGriev = superUser || can(Permission.viewGrievances) || can(Permission.submitGrievances) || can(Permission.manageSupport);
    final showAssets = superUser || can(Permission.viewAssetRequests) || can(Permission.submitAssetRequests) || can(Permission.manageSupport);

    final tabs = <Tab>[
      if (showBugs) const Tab(text: 'Bugs'),
      if (showGriev) const Tab(text: 'Grievances'),
      if (showAssets) const Tab(text: 'Assets'),
    ];
    final views = <Widget>[
      if (showBugs) const _BugsTab(),
      if (showGriev) const _GrievancesTab(),
      if (showAssets) const _AssetsTab(),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support')),
        drawer: const AppDrawer(currentRoute: '/support'),
        body: const Center(child: Text('You do not have access to Support.')),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Support'),
          bottom: TabBar(tabs: tabs),
        ),
        drawer: const AppDrawer(currentRoute: '/support'),
        body: TabBarView(children: views),
      ),
    );
  }
}

// ════════════════ Bugs ════════════════
class _BugsTab extends ConsumerWidget {
  const _BugsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bugsProvider);
    final perms = ref.watch(permissionsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final canManage = auth.isAdmin || auth.isVp || perms.has(Permission.viewBugReports) || perms.has(Permission.manageSupport);
    final canSubmit = canManage || perms.has(Permission.submitBugReports);

    return _ListScaffold(
      newLabel: 'Report a bug',
      canCreate: canSubmit,
      onCreate: () => _showBugForm(context, ref),
      onRefresh: () async {
        ref.invalidate(bugsProvider);
        await ref.read(bugsProvider.future);
      },
      builder: (q) => async.when(
        loading: () => const _Loader(),
        error: (e, _) => _Err('$e'),
        data: (bugs) {
          final list = bugs.where((b) => b.title.toLowerCase().contains(q)).toList();
          if (list.isEmpty) return const _Empty('No bug reports.');
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              for (final b in list)
                _Card(
                  title: b.title,
                  badge: _Badge(b.status ?? 'open', bugStatusColors(b.status)),
                  meta: 'Reported by ${b.reporterName ?? 'Employee'}',
                  subtitle: b.description,
                  onTap: () => _showBugDetail(context, ref, b, canManage),
                ),
            ],
          );
        },
      ),
    );
  }
}

void _showBugForm(BuildContext context, WidgetRef ref) {
  final title = TextEditingController();
  final desc = TextEditingController();
  _formSheet(
    context,
    heading: 'Report a bug',
    fields: [
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Title *')),
      const SizedBox(height: 12),
      TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Description *', hintText: 'Steps to reproduce, what happened…')),
    ],
    onSubmit: () async {
      if (title.text.trim().isEmpty || desc.text.trim().isEmpty) return 'Title and description are required.';
      await ref.read(supportRepositoryProvider).createBug(title.text, desc.text);
      ref.invalidate(bugsProvider);
      return null;
    },
  );
}

void _showBugDetail(BuildContext context, WidgetRef ref, BugReport b, bool canManage) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DetailSheet(
      title: b.title,
      children: [
        _Badge(b.status ?? 'open', bugStatusColors(b.status)),
        const SizedBox(height: 8),
        Text(b.description),
        if (canManage) ...[
          const SizedBox(height: 12),
          _StatusPicker(
            label: 'Status',
            value: b.status ?? 'open',
            options: kBugStatuses,
            onChanged: (s) async {
              await ref.read(supportRepositoryProvider).updateBugStatus(b.id, s);
              ref.invalidate(bugsProvider);
            },
          ),
        ],
        const Divider(height: 24),
        _CommentsThread(
          provider: bugCommentsProvider(b.id),
          onPost: (content, _) async {
            await ref.read(supportRepositoryProvider).postBugComment(b.id, content);
          },
          onPosted: () => ref.invalidate(bugCommentsProvider(b.id)),
        ),
      ],
    ),
  );
}

// ════════════════ Grievances ════════════════
class _GrievancesTab extends ConsumerWidget {
  const _GrievancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(grievancesProvider);
    final auth = ref.watch(authControllerProvider);
    final perms = ref.watch(permissionsControllerProvider);
    final isManager = grievanceIsManager(ref);
    final canSubmit = isManager || perms.has(Permission.submitGrievances) || auth.isAdmin || auth.isVp;

    return _ListScaffold(
      newLabel: 'New grievance',
      canCreate: canSubmit,
      onCreate: () => _showGrievanceForm(context, ref),
      onRefresh: () async {
        ref.invalidate(grievancesProvider);
        await ref.read(grievancesProvider.future);
      },
      builder: (q) => async.when(
        loading: () => const _Loader(),
        error: (e, _) => _Err('$e'),
        data: (items) {
          final list = items.where((g) => g.title.toLowerCase().contains(q)).toList();
          if (list.isEmpty) return const _Empty('No grievances.');
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              for (final g in list)
                _Card(
                  title: g.title,
                  badge: _Badge(grievanceStatusLabel(g.status), grievanceStatusColors(g.status)),
                  trailing: g.priority != null ? _Badge(g.priority!, priorityColors(g.priority)) : null,
                  meta: '${g.category ?? '—'} · ${g.displayName(viewerUid: auth.user!.id, isAdmin: auth.isAdmin, isVp: auth.isVp)}',
                  subtitle: g.details,
                  onTap: () => _showGrievanceDetail(context, ref, g, isManager),
                ),
            ],
          );
        },
      ),
    );
  }
}

void _showGrievanceForm(BuildContext context, WidgetRef ref) {
  final title = TextEditingController();
  final details = TextEditingController();
  String category = kGrievanceCategories.first;
  String priority = 'Medium';
  bool anon = false;
  String visibility = 'nobody';
  _formSheet(
    context,
    heading: 'New grievance',
    statefulFields: (setLocal) => [
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Title *')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: category,
        decoration: const InputDecoration(labelText: 'Category *'),
        items: [for (final c in kGrievanceCategories) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setLocal(() => category = v ?? category),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: priority,
        decoration: const InputDecoration(labelText: 'Priority *'),
        items: [for (final p in kGrievancePriorities) DropdownMenuItem(value: p, child: Text(p))],
        onChanged: (v) => setLocal(() => priority = v ?? priority),
      ),
      const SizedBox(height: 12),
      TextField(controller: details, maxLines: 4, decoration: const InputDecoration(labelText: 'Details *')),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Submit anonymously'),
        value: anon,
        onChanged: (v) => setLocal(() => anon = v),
      ),
      if (anon)
        DropdownButtonFormField<String>(
          initialValue: visibility,
          decoration: const InputDecoration(labelText: 'Anonymous visibility'),
          items: [for (final v in kAnonymousVisibility) DropdownMenuItem(value: v.$1, child: Text(v.$2))],
          onChanged: (v) => setLocal(() => visibility = v ?? visibility),
        ),
    ],
    onSubmit: () async {
      if (title.text.trim().isEmpty || details.text.trim().isEmpty) return 'Title and details are required.';
      await ref.read(supportRepositoryProvider).createGrievance(
            title: title.text,
            category: category,
            priority: priority,
            details: details.text,
            isAnonymous: anon,
            anonymousVisibility: visibility,
          );
      ref.invalidate(grievancesProvider);
      return null;
    },
  );
}

void _showGrievanceDetail(BuildContext context, WidgetRef ref, Grievance g, bool isManager) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DetailSheet(
      title: g.title,
      children: [
        Wrap(spacing: 8, children: [
          _Badge(grievanceStatusLabel(g.status), grievanceStatusColors(g.status)),
          if (g.priority != null) _Badge(g.priority!, priorityColors(g.priority)),
          if (g.category != null) _Badge(g.category!, (const Color(0xFFE0E7FF), const Color(0xFF4F46E5))),
        ],),
        const SizedBox(height: 8),
        if (g.details != null) Text(g.details!),
        if (isManager) ...[
          const SizedBox(height: 12),
          _StatusPicker(
            label: 'Status',
            value: g.status ?? 'submitted',
            options: kGrievanceStatuses,
            labelFor: grievanceStatusLabel,
            onChanged: (s) async {
              await ref.read(supportRepositoryProvider).updateGrievanceStatus(g.id, s, g.userId);
              ref.invalidate(grievancesProvider);
            },
          ),
        ],
        const Divider(height: 24),
        _CommentsThread(
          provider: grievanceCommentsProvider(g.id),
          allowInternal: isManager,
          onPost: (content, internal) async {
            await ref.read(supportRepositoryProvider).postGrievanceComment(
                  g.id, content, isInternal: internal, submitterUid: g.userId,);
          },
          onPosted: () => ref.invalidate(grievanceCommentsProvider(g.id)),
        ),
      ],
    ),
  );
}

// ════════════════ Asset requests ════════════════
class _AssetsTab extends ConsumerStatefulWidget {
  const _AssetsTab();
  @override
  ConsumerState<_AssetsTab> createState() => _AssetsTabState();
}

class _AssetsTabState extends ConsumerState<_AssetsTab> {
  bool _mineOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(assetRequestsProvider);
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    final perms = ref.watch(permissionsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final canSubmit = auth.isAdmin || auth.isVp || perms.has(Permission.submitAssetRequests) || perms.has(Permission.manageSupport);

    return _ListScaffold(
      newLabel: 'New request',
      canCreate: canSubmit,
      onCreate: _showAssetForm,
      onRefresh: () async {
        ref.invalidate(assetRequestsProvider);
        await ref.read(assetRequestsProvider.future);
      },
      extraHeader: Row(
        children: [
          FilterChip(
            label: const Text('My requests'),
            selected: _mineOnly,
            onSelected: (v) => setState(() => _mineOnly = v),
          ),
        ],
      ),
      builder: (q) => async.when(
        loading: () => const _Loader(),
        error: (e, _) => _Err('$e'),
        data: (reqs) {
          var list = reqs.where((r) => r.title.toLowerCase().contains(q)).toList();
          if (_mineOnly) list = list.where((r) => r.userId == uid).toList();
          if (list.isEmpty) return const _Empty('No asset requests.');
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            children: [
              for (final r in list)
                _Card(
                  title: r.title,
                  badge: _Badge(_stageLabel(r), _stageColors(r)),
                  meta: '${r.requestType == 'it_support' ? 'IT support' : 'Asset'} · ${r.requesterName ?? 'Employee'}',
                  subtitle: r.description,
                  onTap: () => _showAssetDetail(r),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAssetForm() {
    final title = TextEditingController();
    final desc = TextEditingController();
    String type = 'asset';
    _formSheet(
      context,
      heading: 'New asset / IT request',
      statefulFields: (setLocal) => [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title *')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            DropdownMenuItem(value: 'asset', child: Text('Asset request')),
            DropdownMenuItem(value: 'it_support', child: Text('IT support')),
          ],
          onChanged: (v) => setLocal(() => type = v ?? 'asset'),
        ),
        const SizedBox(height: 12),
        TextField(controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'Description *')),
      ],
      onSubmit: () async {
        if (title.text.trim().isEmpty || desc.text.trim().isEmpty) return 'Title and description are required.';
        await ref.read(assetRepositoryProvider).createRequest(
              title: title.text, description: desc.text, requestType: type,);
        ref.invalidate(assetRequestsProvider);
        return null;
      },
    );
  }

  void _showAssetDetail(AssetRequest r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailSheet(
        title: r.title,
        children: [
          _Badge(_stageLabel(r), _stageColors(r)),
          const SizedBox(height: 8),
          Text(r.description),
          if (r.rejectionReason != null && r.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason: ${r.rejectionReason}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),),
          ],
          const Divider(height: 24),
          AssetCommentsThread(requestId: r.id),
        ],
      ),
    );
  }

  String _stageLabel(AssetRequest r) => switch (r.approvalStage) {
        'pending_line_manager' => 'Pending manager',
        'pending_admin' => 'Pending admin',
        'approved' => 'Approved',
        'declined' => 'Declined',
        _ => r.status ?? 'Pending',
      };

  (Color, Color) _stageColors(AssetRequest r) => switch (r.approvalStage) {
        'approved' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
        'declined' => (const Color(0xFFFEE2E2), const Color(0xFFDC2626)),
        'pending_admin' => (const Color(0xFFDBEAFE), const Color(0xFF2563EB)),
        _ => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      };
}

// ════════════════ Shared widgets ════════════════
class _ListScaffold extends StatefulWidget {
  const _ListScaffold({
    required this.newLabel,
    required this.canCreate,
    required this.onCreate,
    required this.onRefresh,
    required this.builder,
    this.extraHeader,
  });
  final String newLabel;
  final bool canCreate;
  final VoidCallback onCreate;
  final Future<void> Function() onRefresh;
  final Widget Function(String query) builder;
  final Widget? extraHeader;

  @override
  State<_ListScaffold> createState() => _ListScaffoldState();
}

class _ListScaffoldState extends State<_ListScaffold> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search',
                  ),
                  onChanged: (v) => setState(() => _q = v.toLowerCase()),
                ),
              ),
              if (widget.canCreate)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                    onPressed: widget.onCreate,
                  ),
                ),
            ],
          ),
        ),
        if (widget.extraHeader != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: widget.extraHeader!),
        Expanded(
          child: RefreshIndicator(onRefresh: widget.onRefresh, child: widget.builder(_q)),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.badge,
    required this.meta,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });
  final String title;
  final Widget badge;
  final String meta;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (trailing != null) Padding(padding: const EdgeInsets.only(right: 6), child: trailing!),
                  badge,
                ],
              ),
              const SizedBox(height: 4),
              Text(meta, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.colors);
  final String label;
  final (Color, Color) colors;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: colors.$2, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusPicker extends StatelessWidget {
  const _StatusPicker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelFor,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelFor;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : options.first,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(labelFor?.call(o) ?? o))],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class _Err extends StatelessWidget {
  const _Err(this.msg);
  final String msg;
  @override
  Widget build(BuildContext context) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$msg'))]);
}

class _Empty extends StatelessWidget {
  const _Empty(this.msg);
  final String msg;
  @override
  Widget build(BuildContext context) => ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(msg)))]);
}

// ── Generic comments thread (bugs + grievances) ──────────
class _CommentsThread extends ConsumerStatefulWidget {
  const _CommentsThread({
    required this.provider,
    required this.onPost,
    required this.onPosted,
    this.allowInternal = false,
  });
  final ProviderListenable<AsyncValue<List<CommentItem>>> provider;
  final Future<void> Function(String content, bool internal) onPost;
  final VoidCallback onPosted;
  final bool allowInternal;

  @override
  ConsumerState<_CommentsThread> createState() => _CommentsThreadState();
}

class _CommentsThreadState extends ConsumerState<_CommentsThread> {
  final _c = TextEditingController();
  bool _internal = false;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onPost(t, _internal);
      _c.clear();
      widget.onPosted();
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(widget.provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comments', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        async.when(
          loading: () => const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, __) => const Text('Could not load comments.'),
          data: (comments) {
            if (comments.isEmpty) {
              return Text('No comments yet.', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic));
            }
            return Column(
              children: [
                for (final c in comments)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.isInternal
                          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5)
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(c.authorName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            if (c.isInternal) ...[
                              const SizedBox(width: 6),
                              const _Badge('internal', (Color(0xFFEDE9FE), Color(0xFF7C3AED))),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(c.content, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        TextField(controller: _c, minLines: 1, maxLines: 3, decoration: const InputDecoration(isDense: true, hintText: 'Write a comment…')),
        if (widget.allowInternal)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Internal note (managers only)'),
            value: _internal,
            onChanged: (v) => setState(() => _internal = v ?? false),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: _busy ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 16),
            label: const Text('Post'),
            onPressed: _busy ? null : _post,
          ),
        ),
      ],
    );
  }
}

// ── Create form bottom sheet ─────────────────────────────
void _formSheet(
  BuildContext context, {
  required String heading,
  List<Widget>? fields,
  List<Widget> Function(void Function(void Function()))? statefulFields,
  required Future<String?> Function() onSubmit,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _FormSheetBody(heading: heading, fields: fields, statefulFields: statefulFields, onSubmit: onSubmit),
    ),
  );
}

class _FormSheetBody extends StatefulWidget {
  const _FormSheetBody({required this.heading, this.fields, this.statefulFields, required this.onSubmit});
  final String heading;
  final List<Widget>? fields;
  final List<Widget> Function(void Function(void Function()))? statefulFields;
  final Future<String?> Function() onSubmit;
  @override
  State<_FormSheetBody> createState() => _FormSheetBodyState();
}

class _FormSheetBodyState extends State<_FormSheetBody> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final fields = widget.statefulFields?.call(setState) ?? widget.fields ?? const [];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.heading, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...fields,
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      final nav = Navigator.of(context);
                      final err = await widget.onSubmit();
                      if (err != null) {
                        if (mounted) {
                          setState(() {
                          _busy = false;
                          _error = err;
                        });
                        }
                      } else {
                        nav.pop();
                      }
                    },
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }
}
