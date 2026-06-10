import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_models.dart';
import '../data/onboarding_providers.dart';

/// New-hire form (parity with NewHireDialog): creates an employee (probation)
/// and starts an onboarding workflow with the default task checklist.
Future<bool?> showNewHireForm(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _NewHireForm(),
    ),
  );
}

class _NewHireForm extends ConsumerStatefulWidget {
  const _NewHireForm();
  @override
  ConsumerState<_NewHireForm> createState() => _NewHireFormState();
}

class _NewHireFormState extends ConsumerState<_NewHireForm> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _role = TextEditingController();
  final _salary = TextEditingController();
  String? _department;
  String? _location;
  String _payType = 'salary';
  DateTime? _startDate;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _role.dispose();
    _salary.dispose();
    super.dispose();
  }

  String get _salaryLabel => _payType == 'hourly' ? 'Hourly Rate' : (_payType == 'contractor' ? 'Contract Rate' : 'Salary');

  Future<void> _submit() async {
    final first = _first.text.trim(), last = _last.text.trim(), email = _email.text.trim();
    if (first.isEmpty || last.isEmpty || email.isEmpty || _role.text.trim().isEmpty || _department == null || _location == null || _startDate == null) {
      setState(() => _error = 'Please fill in all required fields.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await ref.read(onboardingControllerProvider.notifier).createNewHire(NewHireData(
            firstName: first,
            lastName: last,
            email: email,
            phone: _phone.text,
            role: _role.text,
            department: _department!,
            location: _location!,
            startDate: '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
            salary: _salary.text.trim().isEmpty ? null : double.tryParse(_salary.text.trim()),
            payType: _payType,
          ),);
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add New Hire', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Creates the employee and starts their onboarding checklist.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'First Name *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Last Name *'))),
          ],),
          const SizedBox(height: 10),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email *')),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 10),
          TextField(controller: _role, decoration: const InputDecoration(labelText: 'Job Title *')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _department,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department *'),
                items: [for (final d in kOnbDepartments) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _department = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Location *'),
                items: const [
                  DropdownMenuItem(value: 'US', child: Text('🇺🇸 US')),
                  DropdownMenuItem(value: 'Nepal', child: Text('🇳🇵 Nepal')),
                ],
                onChanged: (v) => setState(() => _location = v),
              ),
            ),
          ],),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2023), lastDate: DateTime(DateTime.now().year + 2));
              if (d != null) setState(() => _startDate = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Start Date *'),
              child: Text(_startDate == null ? 'Select date' : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _payType,
                decoration: const InputDecoration(labelText: 'Pay Type'),
                items: [for (final p in kPayTypes) DropdownMenuItem(value: p.value, child: Text(p.label))],
                onChanged: (v) => setState(() => _payType = v ?? 'salary'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _salary, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _salaryLabel))),
          ],),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Start Onboarding'),
            ),
          ),
        ],
      ),
    );
  }
}
