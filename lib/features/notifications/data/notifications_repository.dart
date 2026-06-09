import '../../../core/supabase/supabase_client.dart';
import 'notification_models.dart';

/// Notifications data access (list + mark read). No schema changes.
class NotificationsRepository {
  String get _uid => supabase.auth.currentUser!.id;

  Future<List<NotificationItem>> fetch() async {
    final rows = await supabase
        .from('notifications')
        .select('id, user_id, title, message, type, link, is_read, read_at, created_at')
        .eq('user_id', _uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => NotificationItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> markAsRead(String id) async {
    await supabase
        .from('notifications')
        .update({'is_read': true, 'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('user_id', _uid);
  }

  Future<void> markAllAsRead() async {
    await supabase
        .from('notifications')
        .update({'is_read': true, 'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', _uid)
        .eq('is_read', false);
  }
}
