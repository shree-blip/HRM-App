import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/loan_models.dart';
import '../data/loans_providers.dart';

/// Loans (Phase 11): My Loans + (manager) Review + (VP) Finance. Request →
/// manager approval → VP approval → disburse → repayments.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final showManager = auth.isLineManager || auth.isManager;
    final showVp = auth.isVp || auth.isAdmin;

    final tabs = <Tab>[
      const Tab(text: 'My Loans'),
      if (showManager) const Tab(text: 'Review'),
      if (showVp) const Tab(text: 'Finance'),
    ];
    final views = <Widget>[
      const _MyLoans(),
      if (showManager) const _ManagerReview(),
      if (showVp) const _Finance(),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: const Text('Loans'), bottom: TabBar(tabs: tabs)),
        drawer: const AppDrawer(currentRoute: '/loans'),
        body: TabBarView(children: views),
      ),
    );
  }
}

// ════════════════ My Loans ════════════════
class _MyLoans extends ConsumerWidget {
  const _MyLoans();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myLoansProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRequestForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Request loan'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLoansProvider);
          await ref.read(myLoansProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
          data: (loans) => loans.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No loans yet. Tap "Request loan".')))])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [for (final l in loans) _LoanCard(loan: l, onTap: () => _showMyDetail(context, ref, l))],
                ),
        ),
      ),
    );
  }
}

void _showMyDetail(BuildContext context, WidgetRef ref, LoanRequest loan) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Consumer(builder: (context, ref, _) {
      final reps = ref.watch(loanRepaymentsProvider(loan.id));
      final theme = Theme.of(context);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Loan · ${loan.amount}', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _statusChip(loan.status),
                const SizedBox(height: 8),
                _kv(context, 'Term', '${loan.termMonths} months'),
                _kv(context, 'Reason', loan.reasonType ?? '—'),
                _kv(context, 'Interest', '${loan.interestRate.toStringAsFixed(1)}% / yr'),
                _kv(context, 'Monthly EMI', loan.emi.toStringAsFixed(2)),
                if (loan.remainingBalance != null) _kv(context, 'Remaining', loan.remainingBalance!.toStringAsFixed(2)),
                if (loan.managerComment != null && loan.managerComment!.isNotEmpty) _kv(context, 'Manager note', loan.managerComment!),
                const Divider(height: 24),
                Text('Repayments', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                reps.when(
                  loading: () => const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (_, __) => const Text('Could not load repayments.'),
                  data: (list) => list.isEmpty
                      ? Text('No repayments recorded.', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic))
                      : Column(children: [
                          for (final r in list)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('Month ${r.monthNumber ?? '-'} · ${r.totalAmount?.toStringAsFixed(2) ?? '-'}'),
                              subtitle: Text('Principal ${r.principalAmount?.toStringAsFixed(2) ?? '-'} · Interest ${r.interestAmount?.toStringAsFixed(2) ?? '-'}'),
                              trailing: Text('Bal ${r.remainingBalance?.toStringAsFixed(2) ?? '-'}'),
                            ),
                        ],),
                ),
              ],
            ),
          ),
        ),
      );
    },),
  );
}

// ════════════════ Manager Review ════════════════
class _ManagerReview extends ConsumerWidget {
  const _ManagerReview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(managerPendingLoansProvider);
    final history = ref.watch(managerLoanHistoryProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(managerPendingLoansProvider);
        ref.invalidate(managerLoanHistoryProvider);
        await ref.read(managerPendingLoansProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _sectionTitle(context, 'Pending your review'),
          ...pending.when(
            loading: () => [const _Loader()],
            error: (e, _) => [Text('Could not load.\n$e')],
            data: (loans) => loans.isEmpty
                ? [const _EmptyLine('Nothing pending.')]
                : [for (final l in loans) _LoanCard(loan: l, showApplicant: true, onTap: () => _reviewDialog(context, ref, l, isVp: false))],
          ),
          const SizedBox(height: 12),
          _sectionTitle(context, 'History'),
          ...history.when(
            loading: () => [const _Loader()],
            error: (e, _) => [Text('$e')],
            data: (loans) => loans.isEmpty ? [const _EmptyLine('No history.')] : [for (final l in loans) _LoanCard(loan: l, showApplicant: true, onTap: () {})],
          ),
        ],
      ),
    );
  }
}

// ════════════════ Finance (VP) ════════════════
class _Finance extends ConsumerWidget {
  const _Finance();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(vpPendingLoansProvider);
    final disbursed = ref.watch(vpDisbursedLoansProvider);
    final history = ref.watch(vpLoanHistoryProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(vpPendingLoansProvider);
        ref.invalidate(vpDisbursedLoansProvider);
        ref.invalidate(vpLoanHistoryProvider);
        await ref.read(vpPendingLoansProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _sectionTitle(context, 'Awaiting decision'),
          ...pending.when(
            loading: () => [const _Loader()],
            error: (e, _) => [Text('$e')],
            data: (loans) => loans.isEmpty
                ? [const _EmptyLine('Nothing pending.')]
                : [for (final l in loans) _LoanCard(loan: l, showApplicant: true, onTap: () => _reviewDialog(context, ref, l, isVp: true))],
          ),
          const SizedBox(height: 12),
          _sectionTitle(context, 'Active (disbursed)'),
          ...disbursed.when(
            loading: () => [const _Loader()],
            error: (e, _) => [Text('$e')],
            data: (loans) => loans.isEmpty
                ? [const _EmptyLine('None active.')]
                : [for (final l in loans) _LoanCard(loan: l, showApplicant: true, onTap: () => _recordRepaymentDialog(context, ref, l))],
          ),
          const SizedBox(height: 12),
          _sectionTitle(context, 'History'),
          ...history.when(
            loading: () => [const _Loader()],
            error: (e, _) => [Text('$e')],
            data: (loans) => loans.isEmpty
                ? [const _EmptyLine('No history.')]
                : [for (final l in loans) _LoanCard(loan: l, showApplicant: true, onTap: () => l.status == 'approved' ? _disburseDialog(context, ref, l) : null)],
          ),
        ],
      ),
    );
  }
}

// ════════════════ Dialogs ════════════════
Future<void> _reviewDialog(BuildContext context, WidgetRef ref, LoanRequest loan, {required bool isVp}) async {
  final comment = TextEditingController();
  final repo = ref.read(loansRepositoryProvider);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Review loan · ${loan.amount}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${loan.applicantName ?? 'Employee'} · ${loan.termMonths} mo · ${loan.reasonType ?? ''}'),
          Text('EMI ${loan.emi.toStringAsFixed(2)} / month'),
          const SizedBox(height: 8),
          TextField(controller: comment, decoration: const InputDecoration(labelText: 'Comment (optional)')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(ctx);
            isVp
                ? await repo.vpDecision(loan, false, comment.text.trim())
                : await repo.managerDecision(loan, false, comment.text.trim());
            _invalidateAll(ref);
            nav.pop();
          },
          child: const Text('Reject', style: TextStyle(color: Color(0xFFDC2626))),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(ctx);
            isVp
                ? await repo.vpDecision(loan, true, comment.text.trim())
                : await repo.managerDecision(loan, true, comment.text.trim());
            _invalidateAll(ref);
            nav.pop();
          },
          child: const Text('Approve'),
        ),
      ],
    ),
  );
}

Future<void> _disburseDialog(BuildContext context, WidgetRef ref, LoanRequest loan) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Disburse loan?'),
      content: Text('Mark ${loan.amount} as disbursed and start repayment?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disburse')),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(loansRepositoryProvider).disburse(loan);
    _invalidateAll(ref);
  }
}

Future<void> _recordRepaymentDialog(BuildContext context, WidgetRef ref, LoanRequest loan) async {
  final amount = TextEditingController(text: loan.emi.toStringAsFixed(2));
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Record repayment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Remaining: ${(loan.remainingBalance ?? loan.amount).toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(ctx);
            final a = double.tryParse(amount.text.trim());
            if (a == null || a <= 0) return;
            await ref.read(loansRepositoryProvider).recordRepayment(loan, a);
            ref.invalidate(loanRepaymentsProvider(loan.id));
            _invalidateAll(ref);
            nav.pop();
          },
          child: const Text('Record'),
        ),
      ],
    ),
  );
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(myLoansProvider);
  ref.invalidate(managerPendingLoansProvider);
  ref.invalidate(managerLoanHistoryProvider);
  ref.invalidate(vpPendingLoansProvider);
  ref.invalidate(vpDisbursedLoansProvider);
  ref.invalidate(vpLoanHistoryProvider);
}

// ════════════════ Request form ════════════════
void _showRequestForm(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _RequestForm(ref: ref),
    ),
  );
}

class _RequestForm extends StatefulWidget {
  const _RequestForm({required this.ref});
  final WidgetRef ref;
  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _amount = TextEditingController();
  final _signature = TextEditingController();
  int _term = 3;
  String _reason = 'general';
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    final emi = loanEmi(amt, _term);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Request a loan', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount *'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _term,
            decoration: const InputDecoration(labelText: 'Term (months)'),
            items: [for (var m = 1; m <= 6; m++) DropdownMenuItem(value: m, child: Text('$m'))],
            onChanged: (v) => setState(() => _term = v ?? 3),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [for (final r in kLoanReasonTypes) DropdownMenuItem(value: r, child: Text(r[0].toUpperCase() + r.substring(1)))],
            onChanged: (v) => setState(() => _reason = v ?? 'general'),
          ),
          const SizedBox(height: 8),
          if (amt > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: Text('Estimated EMI: ${emi.toStringAsFixed(2)} / month for $_term months @ ${kLoanAnnualRate.toStringAsFixed(0)}% p.a.'),
            ),
          const SizedBox(height: 12),
          TextField(controller: _signature, decoration: const InputDecoration(labelText: 'E-signature (type your full name) *')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I consent to automatic payroll deduction'),
            value: _consent,
            onChanged: (v) => setState(() => _consent = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit request'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (_signature.text.trim().isEmpty) {
      setState(() => _error = 'E-signature is required.');
      return;
    }
    if (!_consent) {
      setState(() => _error = 'Payroll-deduction consent is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await widget.ref.read(loansRepositoryProvider).createLoan(
            amount: amt,
            termMonths: _term,
            reasonType: _reason,
            eSignature: _signature.text,
            autoDeductionConsent: _consent,
          );
      widget.ref.invalidate(myLoansProvider);
      nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
      }
    }
  }
}

// ════════════════ Shared bits ════════════════
class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan, required this.onTap, this.showApplicant = false});
  final LoanRequest loan;
  final VoidCallback onTap;
  final bool showApplicant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('${loan.amount}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                _statusChip(loan.status),
              ],),
              const SizedBox(height: 4),
              if (showApplicant && loan.applicantName != null && loan.applicantName!.isNotEmpty)
                Text(loan.applicantName!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text('${loan.termMonths} mo · ${loan.reasonType ?? '—'} · EMI ${loan.emi.toStringAsFixed(0)}/mo',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _statusChip(String status) {
  final (bg, fg) = loanStatusColors(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(loanStatusLabel(status), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

Widget _kv(BuildContext context, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],),
    );

Widget _sectionTitle(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}
