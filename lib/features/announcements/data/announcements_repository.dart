import '../../../core/supabase/supabase_client.dart';
import 'announcement_models.dart';

/// Announcements data access (list/history + create/soft-delete/restore/delete).
/// Mirrors the web: soft-delete via is_active=false; no edit; no targeting.
class AnnouncementsRepository {
  String get _uid => supabase.auth.currentUser!.id;

  /// Whether the current user is listed in `announcement_publishers` (web's
  /// `isPublisher` path: such users can manage announcements regardless of role).
  Future<bool> isPublisher() async {
    final row = await supabase
        .from('announcement_publishers')
        .select('id')
        .eq('user_id', _uid)
        .maybeSingle();
    return row != null;
  }

  Future<List<Announcement>> _enrich(List<Announcement> list) async {
    final ids = list.map((a) => a.createdBy).whereType<String>().toSet().toList();
    if (ids.isEmpty) return list;
    final names = <String, String>{};
    final profs = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name')
        .inFilter('user_id', ids);
    for (final p in profs as List) {
      final m = p as Map;
      names[m['user_id'] as String] =
          '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    }
    return [for (final a in list) a.withPublisher(names[a.createdBy] ?? 'System')];
  }

  /// Active (live) announcements: not soft-deleted, not expired, pinned first.
  Future<List<Announcement>> active() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await supabase
        .from('announcements')
        .select('id, title, content, type, is_pinned, is_active, expires_at, created_by, created_at')
        .eq('is_active', true)
        .or('expires_at.is.null,expires_at.gt.$nowIso')
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => Announcement.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    return _enrich(list);
  }

  /// History: soft-deleted OR expired, newest first.
  Future<List<Announcement>> history() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await supabase
        .from('announcements')
        .select('id, title, content, type, is_pinned, is_active, expires_at, created_by, created_at')
        .or('is_active.eq.false,and(is_active.eq.true,expires_at.lt.$nowIso)')
        .order('created_at', ascending: false)
        .limit(50);
    final list = (rows as List)
        .map((r) => Announcement.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    return _enrich(list);
  }

  Future<void> create({
    required String title,
    required String content,
    required String type,
    bool isPinned = false,
    DateTime? expiresAt,
  }) async {
    await supabase.from('announcements').insert({
      'title': title.trim(),
      'content': content.trim(),
      'type': type,
      'is_pinned': isPinned,
      'is_active': true,
      'created_by': _uid,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
    });
    await _notifyAll(title.trim());
  }

  Future<void> softDelete(String id) async {
    await supabase.from('announcements').update({'is_active': false}).eq('id', id);
  }

  Future<void> restore(String id) async {
    await supabase
        .from('announcements')
        .update({'is_active': true, 'expires_at': null}).eq('id', id);
  }

  Future<void> permanentDelete(String id) async {
    await supabase.from('announcements').delete().eq('id', id);
  }

  Future<void> _notifyAll(String title) async {
    try {
      final profs = await supabase.from('profiles').select('user_id');
      for (final p in profs as List) {
        final uid = (p as Map)['user_id'] as String?;
        if (uid == null || uid == _uid) continue;
        await supabase.rpc('create_notification', params: {
          'p_user_id': uid,
          'p_title': '📢 New Announcement',
          'p_message': 'New announcement: "$title"',
          'p_type': 'announcement',
          'p_link': '/announcements',
        },);
      }
    } catch (_) {}
  }
}
