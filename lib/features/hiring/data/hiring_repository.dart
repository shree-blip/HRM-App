import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import 'hiring_models.dart';

/// Hiring data access — mirrors the web Hiring page. No schema changes; uses
/// the existing `hiring_posts` table + public `hiring-attachments` bucket.
class HiringRepository {
  Future<List<HiringPost>> list() async {
    final rows = await supabase.from('hiring_posts').select('*').order('created_at', ascending: false);
    return (rows as List).map((r) => HiringPost.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  /// Create a post (optionally uploading an attachment to the public bucket),
  /// then broadcast an in-app notification to all active users — like the web.
  Future<void> create({
    required String title,
    required String content,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    String? attachmentUrl;
    String? attachmentName;

    if (fileBytes != null && fileName != null && fileName.isNotEmpty) {
      final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
      final rand = Random().nextInt(1 << 32).toRadixString(36);
      final path = '${DateTime.now().millisecondsSinceEpoch}-$rand.$ext';
      await supabase.storage.from('hiring-attachments').uploadBinary(
            path,
            fileBytes,
            fileOptions: const FileOptions(upsert: false),
          );
      attachmentUrl = supabase.storage.from('hiring-attachments').getPublicUrl(path);
      attachmentName = fileName;
    }

    await supabase.from('hiring_posts').insert({
      'title': title.trim(),
      'content': content.trim(),
      'attachment_url': attachmentUrl,
      'attachment_name': attachmentName,
      'created_by': supabase.auth.currentUser?.id,
    });

    await _broadcast();
  }

  Future<void> delete(String id) async {
    await supabase.from('hiring_posts').delete().eq('id', id);
  }

  /// Notify all active users (in-app bell) about a new hiring update,
  /// excluding the actor — mirrors notifyUsers(getAllActiveUserIds()).
  Future<void> _broadcast() async {
    try {
      final me = supabase.auth.currentUser?.id;
      final rows = await supabase.from('profiles').select('user_id, status').not('user_id', 'is', null);
      final ids = <String>{};
      for (final r in rows as List) {
        final m = r as Map;
        final uid = m['user_id'] as String?;
        final status = (m['status'] ?? 'active') as String;
        if (uid != null && uid != me && status != 'inactive') ids.add(uid);
      }
      for (final uid in ids) {
        try {
          await supabase.rpc('create_notification', params: {
            'p_user_id': uid,
            'p_title': '💼 New Hiring Update',
            'p_message': 'New hiring update from Focus Your Finance. Please check the Hiring section.',
            'p_type': 'info',
            'p_link': '/hiring',
          },);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
