import '../../../core/supabase/supabase_client.dart';
import 'loan_models.dart';

/// Loans data access: request + 2-stage approval (manager -> VP) + disburse +
/// repayments. Mirrors the web loan_requests / loan_approvals / loan_repayments.
class LoansRepository {
  static const _cols =
      'id, user_id, amount, term_months, reason_type, status, interest_rate, '
      'estimated_monthly_installment, remaining_balance, manager_comment, '
      'created_at, submitted_at';
  static const _colsEmp = '$_cols, employees(first_name, last_name)';

  String get _uid => supabase.auth.currentUser!.id;

  // ── Employee view ─────────────────────────────────────
  Future<List<LoanRequest>> myLoans() async {
    final rows = await supabase
        .from('loan_requests')
        .select(_cols)
        .eq('user_id', _uid)
        .order('created_at', ascending: false);
    return _map(rows);
  }

  Future<({String? employeeId, String? orgId, String? managerUserId, String? vpUserId})> _context() async {
    String? empId;
    try {
      final r = await supabase.rpc('get_employee_id_for_user', params: {'_user_id': _uid});
      if (r is String) empId = r;
    } catch (_) {}
    String? orgId;
    String? managerUserId;
    if (empId != null) {
      try {
        final e = await supabase.from('employees').select('org_id').eq('id', empId).maybeSingle();
        orgId = e?['org_id'] as String?;
      } catch (_) {}
      // Resolve a line manager's user_id via team_members -> employees -> profiles.
      try {
        final tm = await supabase
            .from('team_members')
            .select('manager_employee_id')
            .eq('member_employee_id', empId)
            .limit(1);
        final mgrEmp = (tm as List).isNotEmpty ? (tm.first as Map)['manager_employee_id'] as String? : null;
        if (mgrEmp != null) {
          final me = await supabase.from('employees').select('profile_id').eq('id', mgrEmp).maybeSingle();
          final pid = me?['profile_id'] as String?;
          if (pid != null) {
            final pr = await supabase.from('profiles').select('user_id').eq('id', pid).maybeSingle();
            managerUserId = pr?['user_id'] as String?;
          }
        }
      } catch (_) {}
    }
    String? vpUserId;
    try {
      final v = await supabase.rpc('get_vp_user_id');
      if (v is String) vpUserId = v;
    } catch (_) {}
    return (employeeId: empId, orgId: orgId, managerUserId: managerUserId, vpUserId: vpUserId);
  }

  Future<void> createLoan({
    required num amount,
    required int termMonths,
    required String reasonType,
    required String eSignature,
    required bool autoDeductionConsent,
  }) async {
    final ctx = await _context();
    final emi = loanEmi(amount, termMonths);
    final status = ctx.managerUserId != null ? 'pending_manager' : 'pending_vp';
    final now = DateTime.now().toUtc().toIso8601String();
    await supabase.from('loan_requests').insert({
      'user_id': _uid,
      if (ctx.employeeId != null) 'employee_id': ctx.employeeId,
      if (ctx.orgId != null) 'org_id': ctx.orgId,
      'amount': amount,
      'term_months': termMonths,
      'reason_type': reasonType,
      'interest_rate': kLoanAnnualRate,
      'estimated_monthly_installment': double.parse(emi.toStringAsFixed(2)),
      'auto_deduction_consent': autoDeductionConsent,
      'declaration_signed': true,
      'e_signature': eSignature.trim(),
      'signed_at': now,
      'status': status,
      'submitted_at': now,
      if (ctx.managerUserId != null) 'manager_user_id': ctx.managerUserId,
      if (ctx.vpUserId != null) 'vp_user_id': ctx.vpUserId,
    });
    final target = ctx.managerUserId ?? ctx.vpUserId;
    if (target != null) {
      await _notify(target, '💰 Loan Request',
          'A loan request for $amount needs your review.',);
    }
    // Email to VP — same edge function + payload as the web useLoans
    // submitLoan; best-effort like the web's try/catch.
    try {
      final prof = await supabase
          .from('profiles')
          .select('first_name, last_name, email')
          .eq('user_id', _uid)
          .single();
      final empName =
          '${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'.trim();
      await supabase.functions.invoke('send-loan-notification', body: {
        'event_type': 'submitted',
        'employee_name': empName.isEmpty ? 'An employee' : empName,
        'employee_email': (prof['email'] ?? '') as String,
        'amount': amount,
        'term_months': termMonths,
        'emi': double.parse(emi.toStringAsFixed(2)),
        'reason_type': reasonType,
      },);
    } catch (_) {}
  }

  // ── Manager review ────────────────────────────────────
  Future<List<LoanRequest>> managerPending() => _withEmp(
      supabase.from('loan_requests').select(_colsEmp).eq('manager_user_id', _uid).eq('status', 'pending_manager').order('submitted_at', ascending: true),);

  Future<List<LoanRequest>> managerHistory() => _withEmp(
      supabase.from('loan_requests').select(_colsEmp).eq('manager_user_id', _uid).not('status', 'in', '(pending_manager,draft)').order('created_at', ascending: false),);

  Future<void> managerDecision(LoanRequest loan, bool approved, String? comment) async {
    await supabase.from('loan_requests').update({
      'status': approved ? 'pending_vp' : 'rejected',
      'manager_comment': comment,
      'manager_approved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', loan.id);
    await _logApproval(loan.id, 'manager_review', approved ? 'approved' : 'rejected', comment);
    await _notify(loan.userId, '💰 Loan Update',
        approved ? 'Your loan was approved by your manager and sent to VP.' : 'Your loan was rejected by your manager.',);
  }

  // ── VP / Finance ──────────────────────────────────────
  Future<List<LoanRequest>> vpPending() => _withEmp(
      supabase.from('loan_requests').select(_colsEmp).inFilter('status', ['pending_manager', 'pending_vp']).order('submitted_at', ascending: true),);

  Future<List<LoanRequest>> vpDisbursed() => _withEmp(
      supabase.from('loan_requests').select(_colsEmp).eq('status', 'disbursed').order('created_at', ascending: false),);

  Future<List<LoanRequest>> vpHistory() => _withEmp(
      supabase.from('loan_requests').select(_colsEmp).inFilter('status', ['approved', 'rejected', 'closed']).order('created_at', ascending: false),);

  Future<void> vpDecision(LoanRequest loan, bool approved, String? comment) async {
    await supabase.from('loan_requests').update({
      'status': approved ? 'approved' : 'rejected',
    }).eq('id', loan.id);
    await _logApproval(loan.id, 'vp_review', approved ? 'approved' : 'rejected', comment);
    await _notify(loan.userId, '💰 Loan Update',
        approved ? 'Your loan was approved and is ready to disburse.' : 'Your loan was rejected.',);
    // Email to the employee — same edge function + payload as the web
    // useLoans vpDecision; best-effort like the web's try/catch.
    try {
      final emp = await supabase
          .from('profiles')
          .select('first_name, last_name, email')
          .eq('user_id', loan.userId)
          .single();
      final email = (emp['email'] ?? '') as String;
      if (email.isNotEmpty) {
        final vp = await supabase
            .from('profiles')
            .select('first_name, last_name')
            .eq('user_id', _uid)
            .maybeSingle();
        final vpName = vp != null
            ? '${vp['first_name'] ?? ''} ${vp['last_name'] ?? ''}'.trim()
            : 'VP';
        await supabase.functions.invoke('send-loan-notification', body: {
          'event_type': approved ? 'approved' : 'rejected',
          'employee_name':
              '${emp['first_name'] ?? ''} ${emp['last_name'] ?? ''}'.trim(),
          'employee_email': email,
          'amount': loan.amount,
          'term_months': loan.termMonths,
          'emi': loan.estimatedMonthlyInstallment,
          'reason_type': loan.reasonType,
          'comment': comment,
          'vp_name': vpName,
        },);
      }
    } catch (_) {}
  }

  Future<void> disburse(LoanRequest loan) async {
    await supabase.from('loan_requests').update({
      'status': 'disbursed',
      'disbursed_at': DateTime.now().toUtc().toIso8601String(),
      'remaining_balance': loan.amount,
    }).eq('id', loan.id);
    await _notify(loan.userId, '💰 Loan Disbursed', 'Your loan has been disbursed.');
  }

  Future<List<LoanRepayment>> repayments(String loanId) async {
    final rows = await supabase
        .from('loan_repayments')
        .select('id, month_number, total_amount, principal_amount, interest_amount, remaining_balance, due_date, created_at')
        .eq('loan_request_id', loanId)
        .order('month_number', ascending: true);
    return (rows as List).map((r) => LoanRepayment.fromMap((r as Map).cast<String, dynamic>())).toList();
  }

  Future<void> recordRepayment(LoanRequest loan, num amount) async {
    final newBalance = (loan.remainingBalance ?? loan.amount) - amount;
    final monthlyRate = loan.interestRate / 100 / 12;
    final interest = (loan.remainingBalance ?? loan.amount) * monthlyRate;
    final principal = amount - interest;
    await supabase.from('loan_repayments').insert({
      'loan_request_id': loan.id,
      'user_id': loan.userId,
      'total_amount': amount,
      'principal_amount': double.parse((principal > 0 ? principal : 0).toStringAsFixed(2)),
      'interest_amount': double.parse((interest > 0 ? interest : 0).toStringAsFixed(2)),
      'remaining_balance': double.parse((newBalance > 0 ? newBalance : 0).toStringAsFixed(2)),
    });
    await supabase.from('loan_requests').update({
      'remaining_balance': double.parse((newBalance > 0 ? newBalance : 0).toStringAsFixed(2)),
      if (newBalance <= 0) 'status': 'closed',
    }).eq('id', loan.id);
  }

  // ── helpers ───────────────────────────────────────────
  Future<void> _logApproval(String loanId, String step, String decision, String? notes) async {
    try {
      await supabase.from('loan_approvals').insert({
        'loan_request_id': loanId,
        'approval_step': step,
        'decision': decision,
        'reviewer_id': _uid,
        'notes': notes,
      });
    } catch (_) {}
  }

  Future<void> _notify(String userId, String title, String message) async {
    if (userId == _uid) return;
    try {
      await supabase.rpc('create_notification', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': 'loan',
        'p_link': '/loans',
      },);
    } catch (_) {}
  }

  List<LoanRequest> _map(dynamic rows) => (rows as List)
      .map((r) => LoanRequest.fromMap((r as Map).cast<String, dynamic>()))
      .toList();

  Future<List<LoanRequest>> _withEmp(Future<dynamic> query) async {
    final rows = await query;
    return _map(rows);
  }
}
