import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leave_calc.dart';
import '../data/leave_providers.dart';

/// Flat leave-type list used by the web AdminLeaveDialog (distinct from the
/// employee request form's category structure).
const List<String> _kAdminLeaveTypes = [
  'Annual Leave',
  'Other Leave - Sick Leave',
  'Other Leave - Extension Request',
  'Other Leave - Medical Emergency',
  'Other Leave - Family Emergency',
  'Other Leave - Travel Complications',
  'Other Leave - Other Emergency',
  'Leave in Lieu',
  'Wedding Leave',
  'Bereavement Leave',
  'Maternity Leave',
  'Paternity Leave',
];

/// Deduction description shown in the info banner — mirrors getDeductionInfo.
String _deductionDescription(String leaveType) {
  if (leaveType == 'Annual Leave' || leaveType.startsWith('Other Leave')) {
    return "Deducted from the employee's Annual Leave balance.";
  }
  if (leaveType.startsWith('Leave in Lieu') || leaveType.startsWith('Leave on Leave')) {
    return "Deducted from the employee's Leave in Lieu balance.";
  }
  if (const ['Wedding Leave', 'Bereavement Leave', 'Maternity Leave', 'Paternity Leave']
      .contains(leaveType)) {
    return 'Special leave — tracked separately, not deducted from Annual Leave.';
  }
  return "Deducted from the employee's Annual Leave balance.";
}

/// Admin/VP "Assign Leave" dialog — applies auto-approved leave on behalf of an
/// employee. Ports the web AdminLeaveDialog (fields, validation, business-day
/// calc, half-day). Returns true on success.
Future<bool?> showAdminLeaveDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _AdminLeaveDialog(),
  );
}

class _AdminLeaveDialog extends ConsumerStatefulWidget {
  const _AdminLeaveDialog();
  @override
  ConsumerState<_AdminLeaveDialog> createState() => _AdminLeaveDialogState();
}

class _AdminLeaveDialogState extends ConsumerState<_AdminLeaveDialog> {
  String? _userId;
  String? _leaveType;
  DateTime? _start;
  DateTime? _end;
  final _reason = TextEditingController();
  bool _isHalfDay = false;
  String _halfPeriod = 'first_half';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  double get _days {
    if (_isHalfDay) return 0.5;
    if (_start != null && _end != null) {
      return businessDays(_start!, _end!).toDouble();
    }
    return 0;
  }

  Future<DateTime?> _pickDate(DateTime? initial, {DateTime? first}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: first ?? DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (_userId == null || _leaveType == null || _start == null || reason.isEmpty) {
      setState(() => _error = 'Please fill in all required fields.');
      return;
    }
    if (!_isHalfDay && _end == null) {
      setState(() => _error = 'Please select an end date.');
      return;
    }
    if (!_isHalfDay && businessDays(_start!, _end!) == 0) {
      setState(() => _error = 'Selected dates fall on weekends.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(leaveRepositoryProvider).adminCreateLeave(
            targetUserId: _userId!,
            leaveType: _leaveType!,
            startDate: formatDateKey(_start!),
            endDate: formatDateKey(_isHalfDay ? _start! : _end!),
            days: _days,
            reason: reason,
            isHalfDay: _isHalfDay,
            halfDayPeriod: _isHalfDay ? _halfPeriod : null,
          );
      ref.invalidate(teamLeaveRequestsProvider);
      ref.invalidate(myLeaveRequestsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to assign leave: $e';
        });
      }
    }
  }

  String _fmt(DateTime? d) =>
      d == null ? 'Pick a date' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employees = ref.watch(assignableEmployeesProvider);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.shield_outlined, size: 20),
        SizedBox(width: 8),
        Text('Assign Leave (Admin)'),
      ],),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Employee
              employees.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Could not load employees.'),
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: _userId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Employee', isDense: true,),
                  items: [
                    for (final e in list)
                      DropdownMenuItem(value: e.userId, child: Text(e.name)),
                  ],
                  onChanged: (v) => setState(() => _userId = v),
                ),
              ),
              const SizedBox(height: 12),
              // Leave type
              DropdownButtonFormField<String>(
                initialValue: _leaveType,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Leave Type', isDense: true),
                items: [
                  for (final t in _kAdminLeaveTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _leaveType = v),
              ),
              const SizedBox(height: 12),
              // Half-day
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _isHalfDay,
                title: const Text('Half-Day Leave'),
                onChanged: (v) => setState(() => _isHalfDay = v ?? false),
              ),
              if (_isHalfDay)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'first_half', label: Text('First Half')),
                      ButtonSegment(value: 'second_half', label: Text('Second Half')),
                    ],
                    selected: {_halfPeriod},
                    onSelectionChanged: (s) =>
                        setState(() => _halfPeriod = s.first),
                  ),
                ),
              const SizedBox(height: 4),
              // Dates
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_isHalfDay ? _fmt(_start) : 'Start: ${_fmt(_start)}',
                        overflow: TextOverflow.ellipsis,),
                    onPressed: () async {
                      final d = await _pickDate(_start);
                      if (d != null) setState(() => _start = d);
                    },
                  ),
                ),
                if (!_isHalfDay) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text('End: ${_fmt(_end)}',
                          overflow: TextOverflow.ellipsis,),
                      onPressed: () async {
                        final d = await _pickDate(_end, first: _start);
                        if (d != null) setState(() => _end = d);
                      },
                    ),
                  ),
                ],
              ],),
              if (_start != null && (_isHalfDay || _end != null)) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Leave Duration',
                          style: TextStyle(fontWeight: FontWeight.w600),),
                      Text('${_days == _days.roundToDouble() ? _days.toInt() : _days} '
                          'day${_isHalfDay ? '' : 's'}',),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  hintText: 'Reason for leave assignment…',
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This leave will be auto-approved. '
                      '${_leaveType != null ? _deductionDescription(_leaveType!) : 'Select a leave type to see deduction details.'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Assign Leave'),
        ),
      ],
    );
  }
}
