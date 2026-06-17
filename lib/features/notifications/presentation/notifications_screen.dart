import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/app_drawer.dart';
import '../../announcements/data/announcement_models.dart';
import '../../announcements/data/announcements_providers.dart';
import '../data/notification_models.dart';
import '../data/notifications_providers.dart';

/// A unified feed row (a notification, or an announcement shown as a card).
class _Feed {
  const _Feed({
    required this.id,
    required this.title,
    required this.message,
    this.type,
    this.isRead = false,
    this.isAnnouncement = false,
    this.isPinned = false,
    this.createdAt,
    this.publisherName,
    this.notifId,
    this.link,
  });
  final String id;
  final String title;
  final String message;
  final String? type;
  final bool isRead;
  final bool isAnnouncement;
  final bool isPinned;
  final DateTime? createdAt;
  final String? publisherName;
  final String? notifId; // real notification id (null for announcements)
  final String? link; // deep-link target (web handleNotificationClick)
}

/// Notifications (Critical Fix 2): list + filters (All/Unread/Announcements),
/// mark single/all read, type icons, realtime, merged announcements. Mirrors
/// the web Notifications page.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _filter = 'all'; // all | unread | announcements

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifState = ref.watch(notificationsControllerProvider);
    final announcements = ref.watch(activeAnnouncementsProvider).valueOrNull ?? const <Announcement>[];
    final unread = notifState.unreadCount;

    // Build the merged feed: pinned announcements, notifications, then
    // non-pinned announcements (web ordering).
    final annFeed = [
      for (final a in announcements)
        _Feed(
          id: 'announcement-${a.id}',
          title: a.title,
          message: a.content,
          type: 'announcement',
          isAnnouncement: true,
          isPinned: a.isPinned,
          createdAt: a.createdAt,
          publisherName: a.publisherName,
        ),
    ];
    final notifFeed = [
      for (final n in notifState.items)
        _Feed(
          id: n.id,
          title: n.title,
          message: n.message,
          type: n.type,
          isRead: n.isRead,
          createdAt: n.createdAt,
          notifId: n.id,
          link: n.link,
        ),
    ];
    final all = [
      ...annFeed.where((a) => a.isPinned),
      ...notifFeed,
      ...annFeed.where((a) => !a.isPinned),
    ];
    final list = all.where((f) {
      if (_filter == 'unread') return !f.isRead && !f.isAnnouncement;
      if (_filter == 'announcements') return f.isAnnouncement;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Notifications'),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: theme.colorScheme.error, borderRadius: BorderRadius.circular(20)),
              child: Text('$unread new', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ],),
        actions: [
          if (unread > 0)
            TextButton.icon(
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all'),
              onPressed: () => ref.read(notificationsControllerProvider.notifier).markAllAsRead(),
            ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/notifications'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'unread', label: Text('Unread${unread > 0 ? ' ($unread)' : ''}')),
                ButtonSegment(value: 'announcements', label: Text('News${announcements.isNotEmpty ? ' (${announcements.length})' : ''}')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(notificationsControllerProvider.notifier).refresh();
                ref.invalidate(activeAnnouncementsProvider);
              },
              child: notifState.loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No notifications to show')))])
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          children: [for (final f in list) _row(context, ref, f)],
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, _Feed f) {
    final theme = Theme.of(context);
    final (icon, color) = notificationIcon(f.type);
    final isUnread = !f.isRead && !f.isAnnouncement;
    final cardColor = isUnread
        ? theme.colorScheme.primary.withValues(alpha: 0.06)
        : f.isAnnouncement && f.isPinned
            ? const Color(0xFFFEF3C7).withValues(alpha: 0.5)
            : f.isAnnouncement
                ? const Color(0xFFDBEAFE).withValues(alpha: 0.4)
                : null;

    void tap() {
      if (!f.isAnnouncement && f.notifId != null) {
        ref.read(notificationsControllerProvider.notifier).markAsRead(f.notifId!);
      }
      // Deep-link to the relevant screen (mirrors web handleNotificationClick).
      final link = f.link;
      if (link != null && link.isNotEmpty) context.go(link);
    }

    return Card(
      color: cardColor,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(f.title,
                            style: TextStyle(fontWeight: FontWeight.w600, color: isUnread ? theme.colorScheme.primary : null),),
                        if (f.isAnnouncement)
                          _tag('Announcement', const Color(0xFFD97706)),
                        if (f.isPinned) _tag('Pinned', const Color(0xFFDC2626)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        if (f.publisherName != null && f.publisherName!.isNotEmpty)
                          TextSpan(text: 'By ${f.publisherName}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(text: f.message),
                      ],),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(timeAgo(f.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (isUnread)
                IconButton(
                  icon: const Icon(Icons.check, size: 18),
                  tooltip: 'Mark as read',
                  onPressed: tap,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: c), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}
