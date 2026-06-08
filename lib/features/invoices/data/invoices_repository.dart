import '../../../core/supabase/supabase_client.dart';
import '../../support/data/comment_models.dart';
import 'invoice_models.dart';

/// Invoices data access (create/submit/review + comments). Single-line
/// invoices; no edit/delete (matches the web). No schema changes, no PDF.
class InvoicesRepository {
  static const _cols =
      'id, user_id, invoice_number, invoice_date, due_date, month_of_service, '
      'sender_name, sender_address, sender_email, bill_to_name, bill_to_address, '
      'service_description, amount, currency, payment_account_name, payment_bank_name, '
      'payment_account_number, payment_swift_code, status, submitted_at, reviewed_at, created_at';

  String get _uid => supabase.auth.currentUser!.id;

  Future<({String? employeeId, String? orgId, String name, String email, String? address})> profile() async {
    String name = '';
    String email = '';
    String? address;
    try {
      final p = await supabase
          .from('profiles')
          .select('first_name, last_name, email')
          .eq('user_id', _uid)
          .maybeSingle();
      if (p != null) {
        name = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
        email = (p['email'] ?? '') as String;
      }
    } catch (_) {}
    String? empId;
    String? orgId;
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': _uid});
      if (r is String) empId = r;
    } catch (_) {}
    if (empId != null) {
      try {
        final e = await supabase.from('employees').select('org_id').eq('id', empId).maybeSingle();
        orgId = e?['org_id'] as String?;
      } catch (_) {}
    }
    return (employeeId: empId, orgId: orgId, name: name, email: email, address: address);
  }

  Future<List<Invoice>> myInvoices() async {
    final rows = await supabase
        .from('invoices')
        .select(_cols)
        .eq('user_id', _uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Invoice.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// VP/Admin view: all submitted/approved/rejected invoices (+ submitter).
  Future<List<Invoice>> allInvoices() async {
    final rows = await supabase
        .from('invoices')
        .select('$_cols, employees(first_name, last_name)')
        .inFilter('status', ['submitted', 'approved', 'rejected'])
        .order('submitted_at', ascending: false);
    return (rows as List)
        .map((r) => Invoice.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> createInvoice(Map<String, dynamic> data) async {
    final ctx = await profile();
    await supabase.from('invoices').insert({
      'user_id': _uid,
      if (ctx.employeeId != null) 'employee_id': ctx.employeeId,
      if (ctx.orgId != null) 'org_id': ctx.orgId,
      'status': 'draft',
      'service_description': kServiceDescription,
      ...data,
    });
  }

  Future<void> submitInvoice(String id) async {
    await supabase.from('invoices').update({
      'status': 'submitted',
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> reviewInvoice(String id, String status) async {
    await supabase.from('invoices').update({
      'status': status, // approved | rejected
      'reviewed_by': _uid,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<List<CommentItem>> comments(String id) async {
    final rows = await supabase
        .from('invoice_comments')
        .select('id, user_id, content, created_at')
        .eq('invoice_id', id)
        .order('created_at', ascending: true);
    final list = (rows as List)
        .map((r) => CommentItem.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) return list;
    final ids = list.map((c) => c.userId).toSet().toList();
    final names = <String, String>{};
    final profs = await supabase.from('profiles').select('user_id, first_name, last_name').inFilter('user_id', ids);
    for (final p in profs as List) {
      final m = p as Map;
      names[m['user_id'] as String] = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    }
    return list.map((c) => c.withAuthor(names[c.userId] ?? 'User')).toList();
  }

  Future<void> postComment(String id, String content) async {
    await supabase.from('invoice_comments').insert({
      'invoice_id': id,
      'user_id': _uid,
      'content': content.trim(),
    });
  }
}
