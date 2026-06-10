import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/shell/app_drawer.dart';
import '../data/hiring_models.dart';
import '../data/hiring_providers.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _postedDate(String value) {
  final d = DateTime.tryParse(value);
  if (d == null) return value;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Hiring (parity with the web Hiring page): open roles + referral posts.
/// Everyone can view; Admin/VP can add and delete.
class HiringScreen extends ConsumerWidget {
  const HiringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = canManageHiring(ref);
    final async = ref.watch(hiringPostsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Hiring')),
      drawer: const AppDrawer(currentRoute: '/hiring'),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openCreate(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Hiring Post'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(hiringPostsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Failed to load hiring posts.\n$e', textAlign: TextAlign.center))]),
          data: (posts) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              Text('Open roles and referral opportunities. Refer great people and earn bonuses.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              const SizedBox(height: 12),
              if (posts.isEmpty)
                Card(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                  child: Center(child: Text('No open roles right now.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                ),)
              else
                for (final p in posts) _PostCard(post: p, canManage: canManage),
            ],
          ),
        ),
      ),
    );
  }

  void _openCreate(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const _CreatePostForm(),
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post, required this.canManage});
  final HiringPost post;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Posted ${_postedDate(post.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (canManage)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    onPressed: () => _confirmDelete(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(post.content, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
            if (post.attachmentUrl != null && post.attachmentUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => launchUrl(Uri.parse(post.attachmentUrl!), mode: LaunchMode.externalApplication),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.attach_file, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(child: Text(post.attachmentName ?? 'Attachment', style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  Icon(Icons.download, size: 14, color: theme.colorScheme.primary),
                ],),
              ),
            ],
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
        title: const Text('Delete hiring post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hiringRepositoryProvider).delete(post.id);
      ref.invalidate(hiringPostsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Hiring post deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }
}

class _CreatePostForm extends ConsumerStatefulWidget {
  const _CreatePostForm();
  @override
  ConsumerState<_CreatePostForm> createState() => _CreatePostFormState();
}

class _CreatePostFormState extends ConsumerState<_CreatePostForm> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  Uint8List? _fileBytes;
  String? _fileName;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result != null && result.files.isNotEmpty) {
      final f = result.files.first;
      setState(() {
        _fileBytes = f.bytes;
        _fileName = f.name;
      });
    }
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      setState(() => _error = 'Title and description are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hiringRepositoryProvider).create(
            title: _title.text,
            content: _content.text,
            fileBytes: _fileBytes,
            fileName: _fileName,
          );
      ref.invalidate(hiringPostsProvider);
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Hiring post created')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to create post: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Hiring Post', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', hintText: "e.g. We're hiring an Operations Associate")),
          const SizedBox(height: 10),
          TextField(controller: _content, maxLines: 8, decoration: const InputDecoration(labelText: 'Description', hintText: 'Role details, referral bonus, etc.', alignLabelWithHint: true)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(_fileName ?? 'Attachment (optional, e.g. JD PDF)', overflow: TextOverflow.ellipsis),
            onPressed: _pickFile,
          ),
          if (_fileName != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Remove attachment'),
                onPressed: () => setState(() {
                  _fileBytes = null;
                  _fileName = null;
                }),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Publish'),
            ),
          ),
        ],
      ),
    );
  }
}
