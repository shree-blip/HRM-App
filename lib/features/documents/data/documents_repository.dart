import '../../../core/supabase/supabase_client.dart';
import 'document_models.dart';

/// Documents data access. Visibility is enforced client-side per category
/// (mirrors the web useDocuments rules). The Drive link lives in `file_path`;
/// legacy storage rows resolve to a signed URL. No schema change.
class DocumentsRepository {
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

  /// All documents the current user may see, filtered by the same category
  /// rules the web app applies client-side.
  Future<List<HrDocument>> visibleDocuments({
    required bool isAdmin,
    required bool isVp,
    required bool isManager,
    required bool isLineManager,
  }) async {
    final uid = _uid;
    final rows = await supabase
        .from('documents')
        .select()
        .order('created_at', ascending: false);
    final all = (rows as List)
        .map((r) => HrDocument.fromMap((r as Map).cast<String, dynamic>()))
        .toList();

    String? myEmp;
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': uid});
      if (r is String) myEmp = r;
    } catch (_) {}

    var reportEmpIds = <String>{};
    if ((isLineManager || isManager) && myEmp != null) {
      try {
        final rep = await supabase
            .from('employees')
            .select('id')
            .or('manager_id.eq.$myEmp,line_manager_id.eq.$myEmp');
        reportEmpIds = (rep as List)
            .map((e) => (e as Map)['id'] as String?)
            .whereType<String>()
            .toSet();
      } catch (_) {}
    }

    final visible = all.where((d) {
      switch (d.category) {
        case 'Leave Evidence':
          return d.uploadedBy == uid || isAdmin || isVp || isManager || isLineManager;
        case 'Contracts':
          return d.uploadedBy == uid ||
              isAdmin ||
              isVp ||
              (d.employeeId != null && d.employeeId == myEmp);
        case 'Compliance':
          return d.uploadedBy == uid ||
              isAdmin ||
              isVp ||
              isManager ||
              (d.employeeId != null && d.employeeId == myEmp) ||
              (isLineManager && d.employeeId != null && reportEmpIds.contains(d.employeeId));
        default:
          return true; // Policies and any other category are public.
      }
    }).toList();

    // Resolve uploader + assignee names for display.
    final uploaderIds = visible.map((d) => d.uploadedBy).whereType<String>().toSet().toList();
    final empIds = visible.map((d) => d.employeeId).whereType<String>().toSet().toList();
    final uploaders = <String, String>{};
    final assignees = <String, String>{};
    if (uploaderIds.isNotEmpty) {
      final profs = await supabase
          .from('profiles')
          .select('user_id, first_name, last_name')
          .inFilter('user_id', uploaderIds);
      for (final p in profs as List) {
        final m = p as Map;
        uploaders[m['user_id'] as String] =
            '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      }
    }
    if (empIds.isNotEmpty) {
      final emps = await supabase
          .from('employees')
          .select('id, first_name, last_name')
          .inFilter('id', empIds);
      for (final e in emps as List) {
        final m = e as Map;
        assignees[m['id'] as String] =
            '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      }
    }
    return [
      for (final d in visible)
        d.copyWith(
          uploaderName: d.uploadedBy != null ? uploaders[d.uploadedBy] : null,
          assigneeName: d.employeeId != null ? assignees[d.employeeId] : null,
        ),
    ];
  }

  /// Employees for the assign picker (Contracts / Compliance).
  Future<List<({String id, String name})>> employees() async {
    final rows = await supabase
        .from('employees')
        .select('id, first_name, last_name')
        .order('first_name', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map;
      return (
        id: m['id'] as String,
        name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
      );
    }).toList();
  }

  Future<void> addDocument({
    required String name,
    required String driveUrl,
    required String category,
    String? fileType,
    String? employeeId,
  }) async {
    final ctx = await _context();
    await supabase.from('documents').insert({
      'name': name.trim(),
      'file_path': driveUrl.trim(),
      'file_type': fileType ?? 'link',
      'category': category,
      'status': 'active',
      'uploaded_by': _uid,
      if (employeeId != null) 'employee_id': employeeId,
      if (ctx.orgId != null) 'org_id': ctx.orgId,
    });
  }

  Future<void> updateDocument(
    String id, {
    required String name,
    required String driveUrl,
    String? fileType,
    String? category,
    Object? employeeId = _unset,
  }) async {
    await supabase.from('documents').update({
      'name': name.trim(),
      'file_path': driveUrl.trim(),
      if (fileType != null) 'file_type': fileType,
      if (category != null) 'category': category,
      if (employeeId != _unset) 'employee_id': employeeId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteDocument(HrDocument doc) async {
    if (!doc.isLink && doc.filePath.isNotEmpty) {
      try {
        await supabase.storage.from('documents').remove([doc.filePath]);
      } catch (_) {}
    }
    await supabase.from('documents').delete().eq('id', doc.id);
  }

  /// The launchable URL for a document (the Drive link, or a signed storage URL).
  Future<String> resolveUrl(HrDocument doc) async {
    if (doc.isLink) return doc.filePath;
    return supabase.storage.from('documents').createSignedUrl(doc.filePath, 3600);
  }

  static const _unset = Object();
}
