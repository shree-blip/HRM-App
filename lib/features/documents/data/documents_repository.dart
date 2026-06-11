import '../../../core/supabase/supabase_client.dart';
import 'document_models.dart';

/// One Drive-link document to create (web DriveDocItem).
class DriveDocItem {
  const DriveDocItem({
    required this.name,
    required this.category,
    required this.driveLink,
    this.employeeId,
    this.leaveRequestId,
  });
  final String name;
  final String category;
  final String driveLink;
  final String? employeeId;
  final String? leaveRequestId;
}

/// An employee option for the add/assign pickers.
class DocEmployee {
  const DocEmployee({required this.id, required this.name, this.employeeCode});
  final String id;
  final String name;
  final String? employeeCode;
  String get label => employeeCode != null && employeeCode!.isNotEmpty ? '$name ($employeeCode)' : name;
}

/// Documents data access. Stores Google Drive links in `drive_link`; legacy
/// rows resolve `file_path` to a signed URL. Visibility filtered client-side
/// exactly like the web useDocuments hook. No schema changes.
class DocumentsRepository {
  String get _uid => supabase.auth.currentUser!.id;

  /// Documents the current user may see (web client-side category rules).
  Future<List<HrDocument>> visibleDocuments({
    required bool isAdmin,
    required bool isVp,
    required bool isManager,
    required bool isLineManager,
    required bool hasManageDocuments, // effective manage_documents
    required bool manageDocsOverridden, // explicit override row exists
  }) async {
    final uid = _uid;
    final canManageDocs = isAdmin || isVp || isManager || hasManageDocuments;
    final canManageRestrictedDocs = manageDocsOverridden ? hasManageDocuments : canManageDocs;

    // Resolve my employee id + (for managers) managed report employee ids.
    String? myEmp;
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': uid});
      if (r is String) myEmp = r;
    } catch (_) {}
    var managed = <String>{};
    if ((canManageDocs || isLineManager) && myEmp != null) {
      try {
        final rep = await supabase
            .from('employees')
            .select('id')
            .or('manager_id.eq.$myEmp,line_manager_id.eq.$myEmp');
        managed = (rep as List).map((e) => (e as Map)['id'] as String?).whereType<String>().toSet();
      } catch (_) {}
    }

    final rows = await supabase.from('documents').select().order('created_at', ascending: false);
    final all = (rows as List)
        .map((r) => HrDocument.fromMap((r as Map).cast<String, dynamic>()))
        .toList();

    final visible = all.where((d) {
      switch (d.category) {
        case kLeaveEvidenceCategory:
          if (d.uploadedBy == uid) return true;
          if (manageDocsOverridden) return canManageRestrictedDocs;
          return canManageDocs || isLineManager;
        case 'Contracts':
          if (d.uploadedBy == uid) return true;
          if (d.employeeId != null && myEmp != null && d.employeeId == myEmp) return true;
          return false;
        case 'Compliance':
          if (d.uploadedBy == uid) return true;
          if (d.employeeId != null && myEmp != null && d.employeeId == myEmp) return true;
          if (manageDocsOverridden) return canManageRestrictedDocs;
          if (canManageDocs) return true;
          if (isLineManager && d.employeeId != null && managed.contains(d.employeeId)) return true;
          return false;
        default: // Policies + anything else: public
          return true;
      }
    }).toList();

    // Resolve uploader + assignee names.
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
        uploaders[m['user_id'] as String] = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
      }
    }
    if (empIds.isNotEmpty) {
      final emps = await supabase
          .from('employees')
          .select('id, first_name, last_name')
          .inFilter('id', empIds);
      for (final e in emps as List) {
        final m = e as Map;
        assignees[m['id'] as String] = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
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

  /// Active employees for the pickers.
  Future<List<DocEmployee>> employees() async {
    final rows = await supabase
        .from('employees')
        .select('id, first_name, last_name, employee_id, status')
        .eq('status', 'active')
        .order('first_name', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map;
      return DocEmployee(
        id: m['id'] as String,
        name: '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim(),
        employeeCode: m['employee_id'] as String?,
      );
    }).toList();
  }

  /// The current user's own employee record id (for self-target compliance/leave).
  Future<String?> myEmployeeId() async {
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': _uid});
      if (r is String) return r;
    } catch (_) {}
    return null;
  }

  Future<void> _createOne(DriveDocItem item) async {
    await supabase.from('documents').insert({
      'name': item.name,
      'file_path': null,
      'file_type': 'drive',
      'file_size': null,
      'category': item.category,
      'status': 'active',
      'uploaded_by': _uid,
      'drive_link': item.driveLink.trim(),
      if (item.employeeId != null) 'employee_id': item.employeeId,
      if (item.leaveRequestId != null) 'leave_request_id': item.leaveRequestId,
    });
  }

  /// Bulk-create Drive-link documents. Like the web (useDocuments
  /// sendDocumentNotifications), the email side-effect fires ONCE per logical
  /// action — not once per file — and never blocks the upload.
  Future<void> createDriveDocumentsBulk(
    List<DriveDocItem> items, {
    bool managerUpload = false,
  }) async {
    for (final item in items) {
      await _createOne(item);
    }
    if (items.isNotEmpty) {
      await _sendUploadNotification(items.first, managerUpload: managerUpload);
    }
  }

  /// Email side-effect — same edge function + payload as the web's
  /// send-document-upload-notification call. Best-effort: failures are
  /// swallowed exactly like the web's try/catch.
  Future<void> _sendUploadNotification(
    DriveDocItem item, {
    required bool managerUpload,
  }) async {
    try {
      final uploader = await supabase
          .from('profiles')
          .select('first_name, last_name, email')
          .eq('user_id', _uid)
          .single();
      final uploaderName =
          '${uploader['first_name'] ?? ''} ${uploader['last_name'] ?? ''}'.trim();
      final uploaderEmail = (uploader['email'] ?? '') as String;

      if (managerUpload && item.employeeId != null) {
        final emp = await supabase
            .from('employees')
            .select('first_name, last_name')
            .eq('id', item.employeeId!)
            .maybeSingle();
        final employeeName = emp != null
            ? '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim()
            : 'Employee';
        await supabase.functions.invoke('send-document-upload-notification', body: {
          'uploader_name': uploaderName.isEmpty ? 'User' : uploaderName,
          'uploader_email': uploaderEmail,
          'document_name': item.name,
          'document_category': item.category,
          'employee_id': item.employeeId,
          'employee_name': employeeName,
          'notify_type': 'manager_upload',
        },);
      } else {
        final userEmployeeId = await myEmployeeId();
        await supabase.functions.invoke('send-document-upload-notification', body: {
          'uploader_name': uploaderName.isEmpty ? 'User' : uploaderName,
          'uploader_email': uploaderEmail,
          'document_name': item.name,
          'document_category': item.category,
          'employee_id': userEmployeeId,
          'notify_type': 'employee_upload',
        },);
      }
    } catch (_) {
      // Best-effort; the upload itself already succeeded.
    }
  }

  /// Update the Drive link (Edit / Replace). Returns false if RLS blocked it.
  Future<bool> updateDocumentLink(String id, String newLink) async {
    final data = await supabase
        .from('documents')
        .update({'drive_link': newLink.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    return (data as List).isNotEmpty;
  }

  /// Delete a document (+ legacy storage file). Returns false if RLS blocked it.
  Future<bool> deleteDocument(HrDocument doc) async {
    if (doc.hasLegacyFile) {
      try {
        await supabase.storage.from('documents').remove([doc.filePath!]);
      } catch (_) {}
    }
    final data = await supabase.from('documents').delete().eq('id', doc.id).select('id');
    return (data as List).isNotEmpty;
  }

  /// Launchable URL: the Drive link, or a signed URL for a legacy stored file.
  Future<String?> resolveUrl(HrDocument doc) async {
    if (doc.hasDriveLink) return doc.driveLink!.trim();
    if (doc.hasLegacyFile) {
      try {
        return await supabase.storage.from('documents').createSignedUrl(doc.filePath!, 3600);
      } catch (_) {}
    }
    return null;
  }
}
