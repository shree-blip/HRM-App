import '../../../core/supabase/supabase_client.dart';
import 'comment_models.dart';
import 'support_models.dart';

/// Bug reports + grievances data access (+ comments). Lists rely on RLS for
/// visibility (mirrors the web, which fetches all and lets RLS scope). No
/// schema changes; no file uploads (screenshots/attachments omitted).
class SupportRepository {
  String get _uid => supabase.auth.currentUser!.id;

  Future<({String? employeeId, String? orgId})> _context() async {
    String? empId;
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': _uid});
      if (r is String) empId = r;
    } catch (_) {}
    String? orgId;
    if (empId != null) {
      try {
        final e = await supabase.from('employees').select('org_id').eq('id', empId).maybeSingle();
        orgId = e?['org_id'] as String?;
      } catch (_) {}
    }
    return (employeeId: empId, orgId: orgId);
  }

  Future<Map<String, String>> _names(Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    final profs = await supabase
        .from('profiles')
        .select('user_id, first_name, last_name')
        .inFilter('user_id', ids);
    return {
      for (final p in profs as List)
        (p as Map)['user_id'] as String:
            '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim(),
    };
  }

  Future<void> _notifyAdmins(String title, String message, String type) async {
    try {
      final roles = await supabase
          .from('user_roles')
          .select('user_id')
          .inFilter('role', ['admin', 'vp']);
      final ids = (roles as List)
          .map((r) => (r as Map)['user_id'] as String?)
          .whereType<String>()
          .toSet();
      for (final id in ids) {
        if (id == _uid) continue;
        await supabase.rpc('create_notification', params: {
          'p_user_id': id,
          'p_title': title,
          'p_message': message,
          'p_type': type,
          'p_link': '/support',
        },);
      }
    } catch (_) {}
  }

  Future<void> _notify(String userId, String title, String message, String type) async {
    if (userId == _uid) return;
    try {
      await supabase.rpc('create_notification', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
        'p_link': '/support',
      },);
    } catch (_) {}
  }

  // ── Bug reports ───────────────────────────────────────
  Future<List<BugReport>> bugs() async {
    final rows = await supabase
        .from('bug_reports')
        .select('id, user_id, title, description, status, created_at')
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => BugReport.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    final names = await _names(list.map((b) => b.userId));
    return [for (final b in list) b.withReporter(names[b.userId] ?? 'Employee')];
  }

  Future<void> createBug(String title, String description) async {
    await supabase.from('bug_reports').insert({
      'user_id': _uid,
      'title': title.trim(),
      'description': description.trim(),
      'status': 'open',
    });
    await _notifyAdmins('🐞 New Bug Report', 'A new bug "${title.trim()}" was reported.', 'info');
  }

  Future<void> updateBugStatus(String id, String status) async {
    await supabase.from('bug_reports').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<List<CommentItem>> bugComments(String id) =>
      _comments('bug_report_comments', 'bug_report_id', id);

  Future<void> postBugComment(String id, String content) =>
      _postComment('bug_report_comments', 'bug_report_id', id, content);

  // ── Grievances ────────────────────────────────────────
  Future<List<Grievance>> grievances() async {
    final rows = await supabase
        .from('grievances')
        .select('id, user_id, title, category, priority, details, status, '
            'is_anonymous, anonymous_visibility, assigned_to, created_at')
        .order('created_at', ascending: false);
    final list = (rows as List)
        .map((r) => Grievance.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    final names = await _names(list.map((g) => g.userId));
    return [for (final g in list) g.withSubmitter(names[g.userId] ?? 'Employee')];
  }

  Future<void> createGrievance({
    required String title,
    required String category,
    required String priority,
    required String details,
    bool isAnonymous = false,
    String anonymousVisibility = 'nobody',
  }) async {
    final ctx = await _context();
    await supabase.from('grievances').insert({
      'user_id': _uid,
      if (ctx.employeeId != null) 'employee_id': ctx.employeeId,
      if (ctx.orgId != null) 'org_id': ctx.orgId,
      'title': title.trim(),
      'category': category,
      'priority': priority,
      'details': details.trim(),
      'is_anonymous': isAnonymous,
      'anonymous_visibility': anonymousVisibility,
      'status': 'submitted',
    });
    await _notifyAdmins('📣 New Grievance', 'A new grievance "${title.trim()}" was submitted.', 'grievance');
  }

  Future<void> updateGrievanceStatus(String id, String status, String submitterUid) async {
    await supabase.from('grievances').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
    await _notify(submitterUid, '📣 Grievance Updated',
        'Your grievance status is now "${grievanceStatusLabel(status)}".', 'grievance',);
  }

  /// Grievance comments; non-managers only see non-internal comments.
  Future<List<CommentItem>> grievanceComments(String id, {required bool isManager}) async {
    final all = await _comments('grievance_comments', 'grievance_id', id);
    if (isManager) return all;
    return all.where((c) => !c.isInternal).toList();
  }

  Future<void> postGrievanceComment(
    String id,
    String content, {
    required bool isInternal,
    required String submitterUid,
  }) async {
    await supabase.from('grievance_comments').insert({
      'grievance_id': id,
      'user_id': _uid,
      'content': content.trim(),
      'is_internal': isInternal,
    });
    if (!isInternal) {
      await _notify(submitterUid, '💬 Grievance Comment',
          'There is a new comment on your grievance.', 'grievance',);
    }
  }

  // ── Shared comment helpers ────────────────────────────
  Future<List<CommentItem>> _comments(String table, String parentField, String id) async {
    // Only grievance_comments has an is_internal column.
    final cols = table == 'grievance_comments'
        ? 'id, user_id, content, created_at, is_internal'
        : 'id, user_id, content, created_at';
    final rows = await supabase
        .from(table)
        .select(cols)
        .eq(parentField, id)
        .order('created_at', ascending: true);
    final list = (rows as List)
        .map((r) => CommentItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    final names = await _names(list.map((c) => c.userId));
    return [for (final c in list) c.withAuthor(names[c.userId] ?? 'User')];
  }

  Future<void> _postComment(String table, String parentField, String id, String content) async {
    await supabase.from(table).insert({
      parentField: id,
      'user_id': _uid,
      'content': content.trim(),
    });
  }
}
