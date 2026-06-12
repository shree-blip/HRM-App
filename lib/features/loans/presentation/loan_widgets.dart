import 'package:flutter/material.dart';

import '../data/loan_models.dart';

/// ── Loan Calculator (web LoanCalculator.tsx port) ────────────────────────
/// Amount + term inputs, EMI / total interest / total payment summary, and the
/// estimated reducing-balance amortization table, with the web's EN/NP toggle.

const Map<String, Map<String, String>> _calcLabels = {
  'en': {
    'title': 'Loan Calculator',
    'amount': 'Amount (NPR)',
    'term': 'Term (months)',
    'monthlyEMI': 'Monthly EMI',
    'totalInterest': 'Total Interest',
    'totalPayment': 'Total Payment',
    'schedule': 'Estimated Amortization Schedule',
    'scheduleNote': 'Final schedule confirmed by HR/Finance',
    'month': 'Month',
    'opening': 'Opening',
    'emi': 'EMI',
    'principal': 'Principal',
    'interest': 'Interest',
    'closing': 'Closing',
    'interestBadge': 'Reducing Balance',
    'months': 'months',
  },
  'np': {
    'title': 'ऋण क्याल्कुलेटर',
    'amount': 'रकम (NPR)',
    'term': 'अवधि (महिना)',
    'monthlyEMI': 'मासिक किस्ता',
    'totalInterest': 'कुल ब्याज',
    'totalPayment': 'कुल भुक्तानी',
    'schedule': 'अनुमानित ऋण तालिका',
    'scheduleNote': 'अन्तिम तालिका HR/Finance बाट पुष्टि हुन्छ',
    'month': 'महिना',
    'opening': 'सुरुको बाँकी',
    'emi': 'किस्ता',
    'principal': 'सावाँ',
    'interest': 'ब्याज',
    'closing': 'अन्तिम बाँकी',
    'interestBadge': 'घट्दो शेषमा',
    'months': 'महिना',
  },
};

class LoanCalculatorView extends StatefulWidget {
  const LoanCalculatorView({super.key, this.interestRate = kLoanAnnualRate});
  final double interestRate;

  @override
  State<LoanCalculatorView> createState() => _LoanCalculatorViewState();
}

class _LoanCalculatorViewState extends State<LoanCalculatorView> {
  final _amount = TextEditingController(text: '50000');
  int _term = 6;
  String _lang = 'en';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = _calcLabels[_lang]!;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final schedule =
        amortizationSchedule(amount, _term, annualRate: widget.interestRate);
    final emi = loanEmi(amount, _term, annualRate: widget.interestRate);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.calculate_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l['title']!,
                        style: const TextStyle(fontWeight: FontWeight.bold),),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.interestRate.toStringAsFixed(0)}% p.a. · ${l['interestBadge']}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.translate, size: 16),
                    label: Text(_lang == 'en' ? 'NP' : 'EN'),
                    onPressed: () =>
                        setState(() => _lang = _lang == 'en' ? 'np' : 'en'),
                  ),
                ],),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: l['amount'], isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _term,
                      decoration:
                          InputDecoration(labelText: l['term'], isDense: true),
                      items: [
                        for (var m = 1; m <= 6; m++)
                          DropdownMenuItem(value: m, child: Text('$m ${l['months']}')),
                      ],
                      onChanged: (v) => setState(() => _term = v ?? 6),
                    ),
                  ),
                ],),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    _stat(theme, l['monthlyEMI']!, 'NPR ${emi.toStringAsFixed(2)}',
                        highlight: true,),
                    _stat(theme, l['totalInterest']!,
                        'NPR ${amortizationTotalInterest(schedule).toStringAsFixed(2)}',),
                    _stat(theme, l['totalPayment']!,
                        'NPR ${amortizationTotalPayment(schedule).toStringAsFixed(2)}',),
                  ],),
                ),
                const SizedBox(height: 12),
                Text(l['schedule']!,
                    style: const TextStyle(fontWeight: FontWeight.w600),),
                Text(l['scheduleNote']!,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,),),
                const SizedBox(height: 6),
                AmortizationTable(schedule: schedule, labels: l),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(ThemeData theme, String label, String value,
      {bool highlight = false,}) =>
      Expanded(
        child: Column(children: [
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),),
          const SizedBox(height: 2),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: highlight ? theme.colorScheme.primary : null,
              ),),
        ],),
      );
}

/// Reducing-balance schedule table (web LoanCalculator / LoanRequestForm).
class AmortizationTable extends StatelessWidget {
  const AmortizationTable({super.key, required this.schedule, this.labels});
  final List<AmortizationRow> schedule;
  final Map<String, String>? labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = labels ?? _calcLabels['en']!;
    if (schedule.isEmpty) return const SizedBox.shrink();
    TextStyle h() => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,);
    const c = TextStyle(fontSize: 10);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 32,
        columnSpacing: 14,
        columns: [
          DataColumn(label: Text(l['month']!, style: h())),
          DataColumn(label: Text(l['opening']!, style: h())),
          DataColumn(label: Text(l['emi']!, style: h())),
          DataColumn(label: Text(l['principal']!, style: h())),
          DataColumn(label: Text(l['interest']!, style: h())),
          DataColumn(label: Text(l['closing']!, style: h())),
        ],
        rows: [
          for (final r in schedule)
            DataRow(cells: [
              DataCell(Text('${r.month}', style: c)),
              DataCell(Text(r.openingBalance.toStringAsFixed(2), style: c)),
              DataCell(Text(r.emi.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),),),
              DataCell(Text(r.principal.toStringAsFixed(2), style: c)),
              DataCell(Text(r.interest.toStringAsFixed(2), style: c)),
              DataCell(Text(r.closingBalance.toStringAsFixed(2), style: c)),
            ],),
        ],
      ),
    );
  }
}

/// ── Loan status timeline (web LoanStatusTimeline.tsx port) ───────────────
/// Horizontal step strip: past steps green check, current step highlighted,
/// rejected shown as a banner above (and excluded from the strip).
class LoanStatusTimeline extends StatelessWidget {
  const LoanStatusTimeline({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex = kLoanStatusSteps.indexOf(status);
    final isRejected = status == 'rejected';
    final isClosed = status == 'closed';
    final steps = kLoanStatusSteps.where((s) => s != 'rejected').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isRejected)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cancel_outlined, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Text('Rejected',
                  style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,),),
            ],),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < steps.length; i++) ...[
              Builder(builder: (_) {
                final step = steps[i];
                final stepIndex = kLoanStatusSteps.indexOf(step);
                final isPast = !isRejected && stepIndex < currentIndex;
                final isCurrent = step == status;
                final isClosedStep = step == 'closed';
                final green = isPast || (isClosed && isClosedStep);
                final icon = isClosedStep && isClosed
                    ? Icons.lock_outline
                    : isCurrent
                        ? Icons.schedule
                        : isPast
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined;
                final color = green
                    ? const Color(0xFF16A34A)
                    : isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
                return SizedBox(
                  width: 72,
                  child: Column(children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(height: 2),
                    Text(
                      kLoanStepLabels[step]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: (isCurrent || (isClosed && isClosedStep))
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: color,
                      ),
                    ),
                  ],),
                );
              },),
              if (i < steps.length - 1)
                Container(
                  height: 2,
                  width: 14,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: (!isRejected &&
                          kLoanStatusSteps.indexOf(steps[i]) < currentIndex)
                      ? const Color(0xFF16A34A)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                ),
            ],
          ],),
        ),
      ],
    );
  }
}
