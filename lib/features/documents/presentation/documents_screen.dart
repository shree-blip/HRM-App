import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/document_models.dart';
import '../data/documents_providers.dart';
import 'document_form.dart';

/// Documents (Phase 9): list of HR documents (Google Drive links). Visibility
/// is RLS-style filtered per category; managers/admin/VP see team docs.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  String _category = 'All';
  String _search = '';

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
          final counts = <String, int>{'All': docs.length};
          for (final c in kDocCategories) {
            counts[c] = docs.where((d) => d.category == c).length;
          }
          var list = docs.where((d) {
            if (_category != 'All' && d.category != _category) return false;
            if (_search.isNotEmpty && !d.name.toLowerCase().contains(_search)) return false;
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search documents',
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
                    for (final c in ['All', ...kDocCategories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('$c (${counts[c] ?? 0})'),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(documentsProvider);
                    await ref.read(documentsProvider.future);
                  },
                  child: list.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: Text('No documents.')),
                          ),
                        ],)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                          children: [for (final d in list) _DocCard(doc: d)],
                        ),
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
    final auth = ref.read(authControllerProvider);
    // Contracts: VP/Admin only; other categories: allowed (web parity).
    if (doc.category == 'Contracts') return auth.isVp || auth.isAdmin;
    return true;
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref.read(documentsRepositoryProvider).resolveUrl(doc);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Open failed: $e')));
    }
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
                Expanded(
                  child: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
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
                _meta(theme, Icons.description_outlined, docTypeLabel(doc.fileType)),
                if (isRestrictedCategory(doc.category)) _meta(theme, Icons.lock_outline, 'Private'),
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
                  label: const Text('Open'),
                  onPressed: () => _open(context, ref),
                ),
                const Spacer(),
                if (canManage) ...[
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => showDocumentForm(context, existing: doc),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
    try {
      await ref.read(documentsRepositoryProvider).deleteDocument(doc);
      ref.invalidate(documentsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Widget _meta(ThemeData theme, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
}
