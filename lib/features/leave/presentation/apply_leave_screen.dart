import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leave_calc.dart';
import '../data/leave_providers.dart';

/// Apply Leave form — ports RequestLeaveDialog: category + subtype selection,
/// date range, half-day, leave-in-lieu, and the Payroll/Paid-Leave deduction
/// option with the same auto-Payroll rule.
class ApplyLeaveScreen extends ConsumerStatefulWidget {
  const ApplyLeaveScreen({super.key});

  @override
  ConsumerState<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends ConsumerState<ApplyLeaveScreen> {
  String _category = 'Annual Leave';
  String? _specialSubtype;
  String? _otherSubtype;
  DateTime? _start;
  DateTime? _end;
  bool _isHalfDay = false;
  String _halfPeriod = 'first_half';
  DateTime? _dateWorked;
  DateTime? _lieuDate;
  String _payment = 'Paid Leave';
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isLieu => _category == 'Leave in Lieu';
  bool get _isSpecial => _category == 'Special Leave';
  bool get _isOther => _category == 'Other Leave';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Effective leave_type string stored in the DB.
  String? get _leaveType {
    if (_isSpecial) return _specialSubtype;
    if (_isOther) return _otherSubtype == null ? null : 'Other Leave - $_otherSubtype';
    if (_isLieu) return 'Leave in Lieu';
    return 'Annual Leave';
  }

  double get _days {
    final type = _leaveType;
    if (type == null) return 0;
    if (_isLieu) return 1;
    if (_isSpecial) return computeLeaveDays(leaveType: type, start: _start ?? DateTime.now(), end: _start ?? DateTime.now());
    if (_start == null) return 0;
    if (_isHalfDay) return 0.5;
    return computeLeaveDays(leaveType: type, start: _start!, end: _end ?? _start!);
  }

  @override
  Widget build(BuildContext context) {
    final annualRemaining = ref.watch(annualRemainingProvider).valueOrNull ?? 0;
    final noPaidBalance = annualRemaining <= 0;
    if (noPaidBalance && _payment == 'Paid Leave') _payment = 'Payroll';

    return Scaffold(
      appBar: AppBar(title: const Text('Request Leave')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label('Leave Type'),
          DropdownButtonFormField<String>(
            initialValue: _category,
            items: [
              for (final c in kLeaveCategories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() {
              _category = v!;
              _specialSubtype = null;
              _otherSubtype = null;
              _isHalfDay = false;
              _start = _end = _dateWorked = _lieuDate = null;
            }),
          ),
          const SizedBox(height: 16),

          if (_isSpecial) ..._specialFields(),
          if (_isOther) ..._otherFields(),
          if (_isLieu) ..._lieuFields() else if (!_isSpecial) ..._dateFields(),
          if (_isSpecial) ..._specialDateFields(),

          if (!_isLieu) ...[
            const SizedBox(height: 16),
            _label('Deduction Type'),
            _PaymentChoice(
              value: _payment,
              noPaidBalance: noPaidBalance,
              onChanged: (v) => setState(() => _payment = v),
            ),
            if (noPaidBalance)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('No paid leave balance remaining — using Payroll.',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.error,),),
              ),
          ],

          const SizedBox(height: 16),
          _label(_isLieu ? 'Description of Work Done *' : 'Reason'),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Add details…'),
          ),

          const SizedBox(height: 16),
          _SummaryBox(days: _days, isLieu: _isLieu, isHalfDay: _isHalfDay),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),)
                : const Text('Submit Request'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Field groups ───────────────────────────────────────
  List<Widget> _specialFields() => [
        _label('Special Leave Type'),
        DropdownButtonFormField<String>(
          initialValue: _specialSubtype,
          hint: const Text('Select type'),
          items: [
            for (final e in kSpecialLeaveTypes.entries)
              DropdownMenuItem(value: e.key, child: Text('${e.key} (${e.value} days)')),
          ],
          onChanged: (v) => setState(() {
            _specialSubtype = v;
            if (_start != null && v != null) {
              _end = specialEndDate(_start!, kSpecialLeaveTypes[v]!);
            }
          }),
        ),
        const SizedBox(height: 16),
      ];

  List<Widget> _otherFields() => [
        _label('Reason Category'),
        DropdownButtonFormField<String>(
          initialValue: _otherSubtype,
          hint: const Text('Select reason'),
          items: [
            for (final s in kOtherLeaveSubtypes)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) => setState(() => _otherSubtype = v),
        ),
        const SizedBox(height: 16),
      ];

  List<Widget> _dateFields() => [
        if (!_isSpecial) ...[
          Row(
            children: [
              Checkbox(
                value: _isHalfDay,
                onChanged: (v) => setState(() {
                  _isHalfDay = v ?? false;
                  if (_isHalfDay) _end = _start;
                }),
              ),
              const Text('Half day'),
            ],
          ),
          if (_isHalfDay)
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('First Half (AM)'),
                  selected: _halfPeriod == 'first_half',
                  onSelected: (_) => setState(() => _halfPeriod = 'first_half'),
                ),
                ChoiceChip(
                  label: const Text('Second Half (PM)'),
                  selected: _halfPeriod == 'second_half',
                  onSelected: (_) => setState(() => _halfPeriod = 'second_half'),
                ),
              ],
            ),
          const SizedBox(height: 8),
        ],
        _dateRow(_isHalfDay ? 'Date' : 'Start Date', _start, (d) {
          setState(() {
            _start = d;
            if (_isHalfDay || (_end != null && _end!.isBefore(d))) _end = d;
          });
        }, weekdayOnly: true,),
        if (!_isHalfDay) ...[
          const SizedBox(height: 8),
          _dateRow('End Date', _end, (d) => setState(() => _end = d),
              weekdayOnly: true, firstDate: _start,),
        ],
      ];

  List<Widget> _specialDateFields() => [
        _dateRow('Start Date', _start, (d) {
          setState(() {
            _start = d;
            if (_specialSubtype != null) {
              _end = specialEndDate(d, kSpecialLeaveTypes[_specialSubtype]!);
            }
          });
        }),
        const SizedBox(height: 8),
        if (_end != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text('Ends: ${formatDateKey(_end!)} (auto)',
                style: Theme.of(context).textTheme.bodySmall,),
          ),
      ];

  List<Widget> _lieuFields() => [
        _dateRow('Date You Worked', _dateWorked,
            (d) => setState(() => _dateWorked = d),
            lastDate: DateTime.now(),),
        const SizedBox(height: 8),
        _dateRow('Day You Want Off', _lieuDate,
            (d) => setState(() => _lieuDate = d),
            weekdayOnly: true, firstDate: DateTime.now(),),
      ];

  // ── Helpers ────────────────────────────────────────────
  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),),
      );

  Widget _dateRow(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onPick, {
    bool weekdayOnly = false,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? (firstDate ?? now),
          firstDate: firstDate ?? DateTime(now.year - 1),
          lastDate: lastDate ?? DateTime(now.year + 2),
          selectableDayPredicate: weekdayOnly
              ? (d) => d.weekday != DateTime.saturday && d.weekday != DateTime.sunday
              : null,
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value != null ? formatDateKey(value) : 'Select date'),
      ),
    );
  }

  Future<void> _submit() async {
    final type = _leaveType;
    final reasonText = _reason.text.trim();

    String? err;
    if (type == null) {
      err = 'Please select a leave type.';
    } else if (_isLieu) {
      if (_dateWorked == null || _lieuDate == null) {
        err = 'Select the date you worked and the day you want off.';
      } else if (reasonText.isEmpty) {
        err = 'Please describe the work done.';
      }
    } else if (_isSpecial) {
      if (_start == null) {
        err = 'Select a start date.';
      } else if (reasonText.isEmpty) {
        err = 'Please enter a reason.';
      }
    } else {
      if (_start == null) {
        err = 'Select a start date.';
      } else if (!_isHalfDay && _end == null) {
        err = 'Select an end date.';
      } else if (!_isHalfDay && _days <= 0) {
        err = 'Selected range has no working days.';
      } else if (reasonText.isEmpty) {
        err = 'Please enter a reason.';
      } else if (deductsFromAnnual(type) &&
          _payment == 'Paid Leave' &&
          _days > (ref.read(annualRemainingProvider).valueOrNull ?? 0)) {
        err = 'Not enough paid leave balance for $_days day(s).';
      }
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }

    // Build dates + reason.
    final String startKey, endKey, finalReason;
    if (_isLieu) {
      startKey = formatDateKey(_lieuDate!);
      endKey = startKey;
      finalReason = 'Worked on: ${formatDateKey(_dateWorked!)}. $reasonText';
    } else {
      startKey = formatDateKey(_start!);
      endKey = formatDateKey(_isHalfDay ? _start! : (_end ?? _start!));
      finalReason = '[$_payment] $reasonText';
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(leaveRepositoryProvider).submitRequest(
            leaveType: type!,
            startDate: startKey,
            endDate: endKey,
            days: _days,
            reason: finalReason,
            isHalfDay: _isHalfDay && !_isLieu && !_isSpecial,
            halfDayPeriod:
                (_isHalfDay && !_isLieu && !_isSpecial) ? _halfPeriod : null,
          );
      ref.invalidate(myLeaveRequestsProvider);
      ref.invalidate(leaveBalancesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to submit: $e';
        });
      }
    }
  }
}

class _PaymentChoice extends StatelessWidget {
  const _PaymentChoice({
    required this.value,
    required this.noPaidBalance,
    required this.onChanged,
  });
  final String value;
  final bool noPaidBalance;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Payroll'),
          selected: value == 'Payroll',
          onSelected: (_) => onChanged('Payroll'),
        ),
        ChoiceChip(
          label: const Text('Paid Leave'),
          selected: value == 'Paid Leave',
          onSelected: noPaidBalance ? null : (_) => onChanged('Paid Leave'),
        ),
      ],
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.days, required this.isLieu, required this.isHalfDay});
  final double days;
  final bool isLieu;
  final bool isHalfDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = isLieu
        ? '1 day off in lieu'
        : isHalfDay
            ? '0.5 day (half day)'
            : '${days == days.roundToDouble() ? days.toInt() : days} working day(s)';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.event_note_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Leave Duration: $text',
              style: const TextStyle(fontWeight: FontWeight.w600),),
        ],
      ),
    );
  }
}
