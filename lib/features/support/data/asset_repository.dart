import '../../../core/supabase/supabase_client.dart';
import 'asset_models.dart';
import 'comment_models.dart';

/// Asset request approval data access (read + approve/decline). RLS scopes
/// which requests an approver can see. No schema changes.
class AssetRepository {
  static const _cols =
      'id, user_id, title, description, request_type, approval_stage, status, '
      'rejection_reason, line_manager_approved_at, admin_approved_at, created_at';

  String get _uid => supabase.auth.currentUser!.id;

  /// All visible asset requests (RLS-scoped), with requester names.
  Future<List<AssetRequest>> visibleRequests() async {
    final rows = await supabase
        .from('asset_requests')
        .select(_cols)
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => AssetRequest.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) return list;

    final ids = list.map((r) => r.userId).toSet().toList();
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
    return list
        .map((r) => r.withRequester(names[r.userId] ?? 'Employee'))
        .toList();
  }

  /// Line manager approves -> forwards to admin.
  Future<void> lineManagerApprove(AssetRequest req) async {
    String? empId;
    try {
      final v = await supabase
          .rpc('get_employee_id_for_user', params: {'_user_id': _uid});
      if (v is String) empId = v;
    } catch (_) {}
    await supabase.from('asset_requests').update({
      'approval_stage': 'pending_admin',
      'status': 'pending_admin',
      'line_manager_approved_by': empId,
      'line_manager_approved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', req.id);
    await _notify(req.userId, 'Your asset request was approved by your manager and sent to admin.');
  }

  /// Admin/VP final approval.
  Future<void> adminApprove(AssetRequest req) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await supabase.from('asset_requests').update({
      'approval_stage': 'approved',
      'status': 'approved',
      'admin_approved_by': _uid,
      'admin_approved_at': now,
      'approved_by': _uid,
      'approved_at': now,
    }).eq('id', req.id);
    await _notify(req.userId, 'Your asset request "${req.title}" was approved.');
  }

  Future<void> decline(AssetRequest req, String? reason) async {
    await supabase.from('asset_requests').update({
      'status': 'declined',
      'approval_stage': 'declined',
      'rejection_reason': reason,
      'approved_by': _uid,
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', req.id);
    await _notify(req.userId,
        'Your asset request "${req.title}" was declined${reason != null ? ': $reason' : ''}.',);
  }

  // ── Comments thread (asset_request_comments) ──────────
  Future<List<CommentItem>> comments(String requestId) async {
    final rows = await supabase
        .from('asset_request_comments')
        .select('id, user_id, content, created_at')
        .eq('request_id', requestId)
        .order('created_at', ascending: true);
    final list = (rows as List)
        .map((r) => CommentItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) return list;
    final ids = list.map((c) => c.userId).toSet().toList();
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
    return list.map((c) => c.withAuthor(names[c.userId] ?? 'User')).toList();
  }

  Future<void> postComment(String requestId, String content) async {
    await supabase.from('asset_request_comments').insert({
      'request_id': requestId,
      'user_id': _uid,
      'content': content,
    });
  }

  Future<void> _notify(String userId, String message) async {
    try {
      await supabase.rpc('create_notification', params: {
        'p_user_id': userId,
        'p_title': '🖥️ Asset Request',
        'p_message': message,
        'p_type': 'asset',
        'p_link': '/support',
      },);
    } catch (_) {}
  }
}
