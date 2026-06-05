import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/asset_providers.dart';
import '../data/comment_models.dart';

/// Comments/replies thread for an asset request (ports the web CommentsThread).
/// Shows existing comments with author + time and lets the user post a reply.
class AssetCommentsThread extends ConsumerStatefulWidget {
  const AssetCommentsThread({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<AssetCommentsThread> createState() => _AssetCommentsThreadState();
}

class _AssetCommentsThreadState extends ConsumerState<AssetCommentsThread> {
  final _controller = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _fmt(DateTime? utc) {
    if (utc == null) return '';
    // NPT for consistency with the rest of the app.
    final d = utc.add(const Duration(hours: 5, minutes: 45));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} '
        '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(assetRepositoryProvider).postComment(widget.requestId, text);
      _controller.clear();
      ref.invalidate(assetCommentsProvider(widget.requestId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to post: $e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(assetCommentsProvider(widget.requestId));

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant,),
              const SizedBox(width: 6),
              Text(
                async.maybeWhen(
                  data: (c) => 'Comments${c.isNotEmpty ? ' (${c.length})' : ''}',
                  orElse: () => 'Comments',
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),),
            ),
            error: (_, __) => const Text('Could not load comments.'),
            data: (comments) {
              if (comments.isEmpty) {
                return Text('No comments yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,),);
              }
              return Column(
                children: [for (final c in comments) _bubble(theme, c)],
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Write a comment…',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: _posting
                  ? const SizedBox(
                      height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2),)
                  : const Icon(Icons.send, size: 16),
              label: const Text('Post Comment'),
              onPressed: _posting ? null : _post,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, CommentItem c) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(c.authorName ?? 'User',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),),
              Text(_fmt(c.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,),),
            ],
          ),
          const SizedBox(height: 2),
          Text(c.content, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
