import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/document_models.dart';
import '../data/documents_providers.dart';
import '../data/drive_links.dart';
import 'document_form.dart';

/// Categories that use the web's employee-first drill-down view.
bool _isEmployeeFirstCategory(String c) => c == 'Contracts' || c == 'Compliance';

/// Documents (Phase 9 + hrm-update parity): Google Drive link documents with
/// per-category bulk add, edit/replace link, inline preview, and the web's
/// exact visibility + permission rules.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String _category = 'All Documents';
  String _search = '';
  String? _employeeId; // drill-down selection for Contracts/Compliance

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      drawer: const AppDrawer(currentRoute: '/documents'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDocumentForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load documents.\n$e', textAlign: TextAlign.center)),
        data: (docs) {
          final counts = <String, int>{'All Documents': docs.length};
          for (final c in kDocCategories) {
            counts[c] = docs.where((d) => d.category == c).length;
          }
          // Employee-first drill-down (web): for Contracts/Compliance, show an
          // employee list first; drilling into one shows that person's docs.
          final employeeFirst = _isEmployeeFirstCategory(_category);
          final showEmployeePicker = employeeFirst && _employeeId == null;

          final list = docs.where((d) {
            if (_category != 'All Documents' && d.category != _category) return false;
            if (employeeFirst && _employeeId != null && d.employeeId != _employeeId) {
              return false;
            }
            if (_search.isNotEmpty && !d.name.toLowerCase().contains(_search)) return false;
            return true;
          }).toList();

          // Employees (id -> name + count) that have docs in this category.
          final empAgg = <String, ({String name, int count})>{};
          if (employeeFirst) {
            for (final d in docs.where((d) =>
                d.category == _category && (d.employeeId ?? '').isNotEmpty,)) {
              final id = d.employeeId!;
              final prev = empAgg[id];
              empAgg[id] = (
                name: d.assigneeName?.isNotEmpty == true ? d.assigneeName! : 'Employee',
                count: (prev?.count ?? 0) + 1,
              );
            }
          }
          final empList = empAgg.entries
              .where((e) => _search.isEmpty ||
                  e.value.name.toLowerCase().contains(_search),)
              .toList();
          final selectedName = _employeeId != null ? empAgg[_employeeId]?.name : null;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: showEmployeePicker
                        ? 'Search employees'
                        : 'Search documents',
                  ),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    for (final c in ['All Documents', ...kDocCategories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: isRestrictedCategory(c)
                              ? Icon(isLeaveEvidenceCategory(c) ? Icons.group_outlined : Icons.lock_outline, size: 14)
                              : null,
                          label: Text('$c (${counts[c] ?? 0})'),
                          selected: _category == c,
                          onSelected: (_) => setState(() {
                            _category = c;
                            _employeeId = null; // reset drill-down
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              // Back-to-employees breadcrumb when drilled in.
              if (employeeFirst && _employeeId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text('All employees · ${selectedName ?? ''}'),
                    onPressed: () => setState(() => _employeeId = null),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(documentsProvider);
                    await ref.read(documentsProvider.future);
                  },
                  child: showEmployeePicker
                      ? (empList.isEmpty
                          ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No documents found')))])
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                              children: [
                                for (final e in empList)
                                  Card(
                                    child: ListTile(
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(e.value.name),
                                      subtitle: Text('${e.value.count} document${e.value.count == 1 ? '' : 's'}'),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => setState(() => _employeeId = e.key),
                                    ),
                                  ),
                              ],
                            ))
                      : (list.isEmpty
                          ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No documents found')))])
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                              children: [for (final d in list) _DocCard(doc: d)],
                            )),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DocCard extends ConsumerWidget {
  const _DocCard({required this.doc});
  final HrDocument doc;

  bool _canManage(WidgetRef ref) {
    // Web: Edit Link + Delete show when category != Contracts || isVP.
    if (doc.category == 'Contracts') return ref.read(authControllerProvider).isVp;
    return true;
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = await ref.read(documentsRepositoryProvider).resolveUrl(doc);
    if (url == null) {
      messenger.showSnackBar(const SnackBar(content: Text('This document has no link to open.')));
      return;
    }
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Could not open the link.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (bg, fg) = statusColors(doc.status);
    final canManage = _canManage(ref);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(categoryIcon(doc.category), color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (doc.status != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(doc.status!, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (doc.category != null) _meta(theme, Icons.folder_outlined, doc.category!),
                if (isRestrictedCategory(doc.category))
                  _meta(theme, isLeaveEvidenceCategory(doc.category) ? Icons.group_outlined : Icons.lock_outline,
                      isLeaveEvidenceCategory(doc.category) ? 'Restricted' : 'Private',),
                if (doc.assigneeName != null && doc.assigneeName!.isNotEmpty)
                  _meta(theme, Icons.person_outline, doc.assigneeName!),
                if (doc.uploaderName != null && doc.uploaderName!.isNotEmpty)
                  _meta(theme, Icons.upload_outlined, doc.uploaderName!),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in Drive'),
                  onPressed: () => _open(context, ref),
                ),
                const Spacer(),
                TextButton(onPressed: () => _showView(context, ref, doc), child: const Text('View')),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _showEditLink(context, ref, doc, 'edit');
                      if (v == 'replace') _showEditLink(context, ref, doc, 'replace');
                      if (v == 'rename') _showRename(context, ref, doc);
                      if (v == 'share') _share(context, ref, doc);
                      if (v == 'delete') _confirmDelete(context, ref, doc);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit Link')),
                      PopupMenuItem(value: 'replace', child: Text('Replace Link')),
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'share', child: Text('Share')),
                      PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Color(0xFFDC2626)))),
                    ],
                  ),
              ],
            ),
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

  /// Share the document's link via the native share sheet (mobile equivalent
  /// of the web ShareDocumentDialog's copy-link).
  Future<void> _share(BuildContext context, WidgetRef ref, HrDocument doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = await ref.read(documentsRepositoryProvider).resolveUrl(doc);
    if (url == null) {
      messenger.showSnackBar(const SnackBar(content: Text('This document has no link to share.')));
      return;
    }
    await Share.share('${doc.name}: $url', subject: doc.name);
  }

  void _showRename(BuildContext context, WidgetRef ref, HrDocument doc) {
    final controller = TextEditingController(text: doc.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Document name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(ctx);
              final ok = await ref
                  .read(documentsRepositoryProvider)
                  .renameDocument(doc.id, name);
              ref.invalidate(documentsProvider);
              nav.pop();
              if (!ok) {
                messenger.showSnackBar(const SnackBar(
                    content: Text("You don't have permission to rename this document."),),);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, HrDocument doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('Remove "${doc.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final allowed = await ref.read(documentsRepositoryProvider).deleteDocument(doc);
    if (!allowed) {
      messenger.showSnackBar(const SnackBar(content: Text("You don't have permission to delete this document.")));
    }
    ref.invalidate(documentsProvider);
  }
}

// ── View dialog (inline Drive preview) ───────────────────
void _showView(BuildContext context, WidgetRef ref, HrDocument doc) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DocumentViewSheet(doc: doc),
  );
}

class _DocumentViewSheet extends ConsumerWidget {
  const _DocumentViewSheet({required this.doc});
  final HrDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final previewUrl = doc.hasDriveLink ? getDrivePreviewUrl(doc.driveLink) : '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Document Preview', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (previewUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 360,
                  child: WebViewWidget(
                    controller: WebViewController()
                      ..setJavaScriptMode(JavaScriptMode.unrestricted)
                      ..loadRequest(Uri.parse(previewUrl)),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Icon(categoryIcon(doc.category), size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(doc.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text((doc.fileType ?? 'FILE').toUpperCase(), style: theme.textTheme.bodySmall),
                ],),
              ),
            const SizedBox(height: 12),
            _kv(theme, 'Category', doc.category ?? 'Uncategorized'),
            _kv(theme, 'Source', doc.hasDriveLink ? 'Google Drive' : 'Stored file'),
            _kv(theme, 'Status', doc.status ?? 'active'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open in Drive'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final url = await ref.read(documentsRepositoryProvider).resolveUrl(doc);
                  if (url != null) {
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  } else {
                    messenger.showSnackBar(const SnackBar(content: Text('No link to open.')));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 90, child: Text(k, style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],),
      );
}

// ── Edit / Replace link dialog ───────────────────────────
void _showEditLink(BuildContext context, WidgetRef ref, HrDocument doc, String mode) {
  final controller = TextEditingController(text: mode == 'edit' ? (doc.driveLink ?? '') : '');
  String? error;
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(mode == 'edit' ? 'Edit Link' : 'Replace Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mode == 'edit'
                ? 'Update the Google Drive link for "${doc.name}".'
                : 'Paste a new Google Drive link for "${doc.name}".',),
            const SizedBox(height: 10),
            TextField(controller: controller, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://drive.google.com/...')),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(kDriveLinkHelperText, style: Theme.of(ctx).textTheme.bodySmall)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!isValidDriveLink(controller.text)) {
                setLocal(() => error = 'Please paste a valid Google Drive link.');
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              final nav = Navigator.of(ctx);
              final allowed = await ref.read(documentsRepositoryProvider).updateDocumentLink(doc.id, controller.text.trim());
              ref.invalidate(documentsProvider);
              nav.pop();
              if (!allowed) {
                messenger.showSnackBar(const SnackBar(content: Text("You don't have permission to update this link.")));
              }
            },
            child: Text(mode == 'edit' ? 'Update Link' : 'Replace Link'),
          ),
        ],
      ),
    ),
  );
}
