import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_drawer.dart';
import '../../../core/auth/auth_controller.dart';
import '../data/invoice_models.dart';
import '../data/invoices_providers.dart';

/// Invoices (Phase 11): My Invoices + (VP/Admin) Submissions. Create draft →
/// submit → review (approve/reject) + comments. No edit/delete (matches web).
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canReview = canReviewInvoices(ref);
    final tabCount = canReview ? 2 : 1;
    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Invoices'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'My Invoices'),
              if (canReview) const Tab(text: 'Submissions'),
            ],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/invoices'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showForm(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
        body: TabBarView(
          children: [
            const _MyInvoices(),
            if (canReview) const _Submissions(),
          ],
        ),
      ),
    );
  }
}

class _MyInvoices extends ConsumerStatefulWidget {
  const _MyInvoices();
  @override
  ConsumerState<_MyInvoices> createState() => _MyInvoicesState();
}

class _MyInvoicesState extends ConsumerState<_MyInvoices> {
  String _q = '';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myInvoicesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search number / client'),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final s in ['all', ...kInvoiceStatuses])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(s), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myInvoicesProvider);
              await ref.read(myInvoicesProvider.future);
            },
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
              data: (items) {
                final list = items.where((i) {
                  if (_status != 'all' && i.status != _status) return false;
                  if (_q.isEmpty) return true;
                  return '${i.invoiceNumber ?? ''} ${i.billToName ?? ''}'.toLowerCase().contains(_q);
                }).toList();
                if (list.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No invoices.')))]);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  children: [for (final i in list) _InvoiceCard(invoice: i, canReview: false)],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Submissions extends ConsumerWidget {
  const _Submissions();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allInvoicesProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(allInvoicesProvider);
        await ref.read(allInvoicesProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load.\n$e'))]),
        data: (items) => items.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No submissions.')))])
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                children: [for (final i in items) _InvoiceCard(invoice: i, canReview: true)],
              ),
      ),
    );
  }
}

class _InvoiceCard extends ConsumerWidget {
  const _InvoiceCard({required this.invoice, required this.canReview});
  final Invoice invoice;
  final bool canReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (bg, fg) = invoiceStatusColors(invoice.status);
    return Card(
      child: InkWell(
        onTap: () => _showDetail(context, ref, invoice, canReview),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(invoice.invoiceNumber ?? '(no number)', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(invoice.status, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${invoice.billToName ?? '—'}  ·  ${invoice.amountDisplay}', style: theme.textTheme.bodyMedium),
              if (invoice.invoiceDate != null)
                Text('Invoice date: ${invoice.invoiceDate}${invoice.dueDate != null ? '  ·  Due: ${invoice.dueDate}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              if (canReview && invoice.submitterName != null && invoice.submitterName!.isNotEmpty)
                Text('By ${invoice.submitterName}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

void _showDetail(BuildContext context, WidgetRef ref, Invoice inv, bool canReview) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _InvoiceDetail(invoice: inv, canReview: canReview),
  );
}

class _InvoiceDetail extends ConsumerStatefulWidget {
  const _InvoiceDetail({required this.invoice, required this.canReview});
  final Invoice invoice;
  final bool canReview;
  @override
  ConsumerState<_InvoiceDetail> createState() => _InvoiceDetailState();
}

class _InvoiceDetailState extends ConsumerState<_InvoiceDetail> {
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Invoice get inv => widget.invoice;

  Future<void> _act(Future<void> Function() f) async {
    final m = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await f();
      ref.invalidate(myInvoicesProvider);
      ref.invalidate(allInvoicesProvider);
      nav.pop();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      m.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    final repo = ref.read(invoicesRepositoryProvider);
    final isOwner = inv.userId == uid;
    final comments = ref.watch(invoiceCommentsProvider(inv.id));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: Text(inv.invoiceNumber ?? 'Invoice', style: theme.textTheme.titleLarge)),
                Builder(builder: (_) {
                  final (bg, fg) = invoiceStatusColors(inv.status);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(inv.status, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
                  );
                },),
              ],),
              const SizedBox(height: 8),
              _kv('From', '${inv.senderName ?? '—'}${inv.senderEmail != null ? '\n${inv.senderEmail}' : ''}'),
              _kv('Bill to', '${inv.billToName ?? '—'}${inv.billToAddress != null ? '\n${inv.billToAddress}' : ''}'),
              _kv('Service', inv.serviceDescription ?? '—'),
              if (inv.monthOfService != null) _kv('Month', inv.monthOfService!),
              _kv('Invoice date', inv.invoiceDate ?? '—'),
              if (inv.dueDate != null) _kv('Due date', inv.dueDate!),
              _kv('Amount', inv.amountDisplay),
              if (inv.paymentBankName != null || inv.paymentAccountNumber != null)
                _kv('Payment', '${inv.paymentAccountName ?? ''} ${inv.paymentBankName ?? ''} ${inv.paymentAccountNumber ?? ''} ${inv.paymentSwiftCode ?? ''}'.trim()),
              const SizedBox(height: 12),
              // Actions
              if (isOwner && inv.status == 'draft')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Submit to executive'),
                    onPressed: _busy ? null : () => _act(() => repo.submitInvoice(inv.id)),
                  ),
                ),
              if (widget.canReview && inv.status == 'submitted')
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: _busy ? null : () => _act(() => repo.reviewInvoice(inv.id, 'rejected')),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _act(() => repo.reviewInvoice(inv.id, 'approved')),
                      child: const Text('Approve'),
                    ),
                  ),
                ],),
              const Divider(height: 24),
              Text('Comments', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              comments.when(
                loading: () => const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                error: (_, __) => const Text('Could not load comments.'),
                data: (list) => list.isEmpty
                    ? Text('No comments yet.', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic))
                    : Column(children: [
                        for (final c in list)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.authorName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(c.content, style: theme.textTheme.bodyMedium),
                            ],),
                          ),
                      ],),
              ),
              const SizedBox(height: 8),
              TextField(controller: _comment, minLines: 1, maxLines: 3, decoration: const InputDecoration(isDense: true, hintText: 'Write a comment…')),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Post'),
                  onPressed: () async {
                    final t = _comment.text.trim();
                    if (t.isEmpty) return;
                    await repo.postComment(inv.id, t);
                    _comment.clear();
                    ref.invalidate(invoiceCommentsProvider(inv.id));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

// ── Create form ──────────────────────────────────────────
void _showForm(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _InvoiceForm(ref: ref),
    ),
  );
}

class _InvoiceForm extends StatefulWidget {
  const _InvoiceForm({required this.ref});
  final WidgetRef ref;
  @override
  State<_InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<_InvoiceForm> {
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _senderName = TextEditingController();
  final _senderAddr = TextEditingController();
  final _senderEmail = TextEditingController();
  final _payName = TextEditingController();
  final _payBank = TextEditingController();
  final _payAcct = TextEditingController();
  final _paySwift = TextEditingController();
  DateTime _date = DateTime.now();
  int _dueDays = 0;
  String _month = kInvoiceMonths[DateTime.now().month - 1];
  String _client = kInvoiceClients.first.$1;
  String _currency = 'NPR';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill sender from profile.
    widget.ref.read(invoicesRepositoryProvider).profile().then((p) {
      if (mounted) {
        _senderName.text = p.name;
        _senderEmail.text = p.email;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_number, _amount, _senderName, _senderAddr, _senderEmail, _payName, _payBank, _payAcct, _paySwift]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final addr = kInvoiceClients.firstWhere((c) => c.$1 == _client).$2;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New invoice', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _number, decoration: const InputDecoration(labelText: 'Invoice number *', hintText: 'INV-001')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 1));
                  if (d != null) setState(() => _date = d);
                },
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Invoice date'), child: Text(_fmt(_date))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _dueDays,
                decoration: const InputDecoration(labelText: 'Due'),
                items: [for (final o in kDueDateOptions) DropdownMenuItem(value: o.$2, child: Text(o.$1))],
                onChanged: (v) => setState(() => _dueDays = v ?? 0),
              ),
            ),
          ],),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _month,
            decoration: const InputDecoration(labelText: 'Month of service'),
            items: [for (final m in kInvoiceMonths) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => setState(() => _month = v ?? _month),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _client,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bill to'),
            items: [for (final c in kInvoiceClients) DropdownMenuItem(value: c.$1, child: Text(c.$1, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _client = v ?? _client),
          ),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(addr, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount *'))),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [for (final c in kInvoiceCurrencies) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => _currency = v ?? 'NPR'),
              ),
            ),
          ],),
          const SizedBox(height: 12),
          TextField(controller: _senderName, decoration: const InputDecoration(labelText: 'Your name')),
          const SizedBox(height: 8),
          TextField(controller: _senderEmail, decoration: const InputDecoration(labelText: 'Your email')),
          const SizedBox(height: 8),
          TextField(controller: _senderAddr, decoration: const InputDecoration(labelText: 'Your address')),
          const SizedBox(height: 12),
          Text('Payment details (optional)', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          TextField(controller: _payName, decoration: const InputDecoration(labelText: 'Account name')),
          const SizedBox(height: 8),
          TextField(controller: _payBank, decoration: const InputDecoration(labelText: 'Bank name')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _payAcct, decoration: const InputDecoration(labelText: 'Account no.'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _paySwift, decoration: const InputDecoration(labelText: 'SWIFT'))),
          ],),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create draft'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim());
    if (_number.text.trim().isEmpty || amt == null || amt <= 0) {
      setState(() => _error = 'Invoice number and a positive amount are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final due = _date.add(Duration(days: _dueDays));
    final addr = kInvoiceClients.firstWhere((c) => c.$1 == _client).$2;
    try {
      await widget.ref.read(invoicesRepositoryProvider).createInvoice({
        'invoice_number': _number.text.trim(),
        'invoice_date': _fmt(_date),
        'due_date': _fmt(due),
        'month_of_service': _month,
        'sender_name': _senderName.text.trim(),
        'sender_address': _senderAddr.text.trim().isEmpty ? null : _senderAddr.text.trim(),
        'sender_email': _senderEmail.text.trim().isEmpty ? null : _senderEmail.text.trim(),
        'bill_to_name': _client,
        'bill_to_address': addr,
        'amount': amt,
        'currency': _currency,
        'payment_account_name': _payName.text.trim().isEmpty ? null : _payName.text.trim(),
        'payment_bank_name': _payBank.text.trim().isEmpty ? null : _payBank.text.trim(),
        'payment_account_number': _payAcct.text.trim().isEmpty ? null : _payAcct.text.trim(),
        'payment_swift_code': _paySwift.text.trim().isEmpty ? null : _paySwift.text.trim(),
      });
      widget.ref.invalidate(myInvoicesProvider);
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
