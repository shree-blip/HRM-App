import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/employee.dart';
import '../data/employees_providers.dart';

const kEmpDepartments = ['Executive', 'Accounting', 'Tax', 'Operations', 'Marketing', 'IT', 'Healthcare', 'Focus Data'];
const kEmpLocations = <(String, String)>[('US', 'United States'), ('Nepal', 'Nepal')];
const kEmpStatuses = ['active', 'probation', 'inactive'];
const kEmploymentTypes = ['full_time', 'probation', 'intern'];
const Map<String, String> kEmploymentTypeLabels = {
  'full_time': 'Full-Time',
  'probation': 'Probation',
  'intern': 'Intern',
};

void _invalidate(WidgetRef ref, String? id) {
  ref.invalidate(employeesListProvider);
  ref.invalidate(employeeManagersProvider);
  if (id != null) {
    ref.invalidate(employeeByIdProvider(id));
    ref.invalidate(employeeRelationsProvider(id));
  }
}

// ════════════════ Add ════════════════
Future<bool?> showAddEmployeeForm(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _AddEmployeeForm(),
    ),
  );
}

class _AddEmployeeForm extends ConsumerStatefulWidget {
  const _AddEmployeeForm();
  @override
  ConsumerState<_AddEmployeeForm> createState() => _AddEmployeeFormState();
}

class _AddEmployeeFormState extends ConsumerState<_AddEmployeeForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _role = TextEditingController();
  final _phone = TextEditingController();
  String? _department;
  String? _location;
  String? _lineManagerId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _role.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty || _role.text.trim().isEmpty || _department == null || _location == null) {
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
    final repo = ref.read(employeesRepositoryProvider);
    try {
      if (await repo.emailExists(email)) {
        setState(() {
          _busy = false;
          _error = 'An employee with this email already exists.';
        });
        return;
      }
      final parts = name.split(RegExp(r'\s+'));
      await repo.createEmployee(
        firstName: parts.first,
        lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        email: email,
        phone: _phone.text,
        department: _department,
        jobTitle: _role.text,
        location: _location!,
        lineManagerId: _lineManagerId,
      );
      _invalidate(ref, null);
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final managers = ref.watch(employeeManagersProvider).valueOrNull ?? const [];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add New Employee', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('They will be able to sign up with their work email.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name *')),
          const SizedBox(height: 10),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email *')),
          const SizedBox(height: 10),
          TextField(controller: _role, decoration: const InputDecoration(labelText: 'Position / Title *', hintText: 'e.g. Staff Accountant')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _department,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department *'),
                items: [for (final d in kEmpDepartments) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _department = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Location *'),
                items: [for (final l in kEmpLocations) DropdownMenuItem(value: l.$1, child: Text(l.$2, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _location = v),
              ),
            ),
          ],),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _lineManagerId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Line Manager (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No line manager')),
              for (final m in managers) DropdownMenuItem(value: m.id, child: Text(m.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _lineManagerId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
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
                  : const Text('Add Employee'),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════ Edit ════════════════
Future<bool?> showEditEmployeeForm(BuildContext context, WidgetRef ref, EmployeeDirectoryItem employee) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _EditEmployeeForm(employee: employee),
    ),
  );
}

class _EditEmployeeForm extends ConsumerStatefulWidget {
  const _EditEmployeeForm({required this.employee});
  final EmployeeDirectoryItem employee;
  @override
  ConsumerState<_EditEmployeeForm> createState() => _EditEmployeeFormState();
}

class _EditEmployeeFormState extends ConsumerState<_EditEmployeeForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _role = TextEditingController();
  String? _department;
  String? _location;
  String _status = 'active';
  String _employmentType = 'full_time';
  String? _dob;
  String? _joining;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = widget.employee;
    // Seed from the directory item, then enrich with the full row (phone).
    _name.text = e.fullName;
    _email.text = e.email;
    _role.text = e.jobTitle ?? '';
    _department = kEmpDepartments.contains(e.department) ? e.department : null;
    _location = e.location == 'Nepal' ? 'Nepal' : (e.location == 'US' ? 'US' : null);
    _status = kEmpStatuses.contains(e.status) ? e.status! : 'active';
    if (kEmploymentTypes.contains(e.employmentType)) {
      _employmentType = e.employmentType!;
    }
    final repo = ref.read(employeesRepositoryProvider);
    try {
      final full = await repo.fullById(e.id);
      if (full != null && mounted) {
        _phone.text = full.phone ?? '';
        if (kEmpDepartments.contains(full.department)) _department = full.department;
        if (full.location == 'US' || full.location == 'Nepal') _location = full.location;
        if (kEmpStatuses.contains(full.status)) _status = full.status!;
        if (kEmploymentTypes.contains(full.employmentType)) {
          _employmentType = full.employmentType!;
        }
      }
    } catch (_) {}
    // Preload milestones from the same source View Profile uses (the linked
    // profiles row), so existing birthday / anniversary show up here too.
    try {
      final ms = await repo.milestones(profileId: e.profileId);
      _dob = (ms.dob?.isNotEmpty == true) ? ms.dob : null;
      _joining = (ms.joining?.isNotEmpty == true) ? ms.joining : null;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Name and email are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final repo = ref.read(employeesRepositoryProvider);
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    try {
      await repo.updateEmployee(
        widget.employee.id,
        firstName: parts.first,
        lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        email: _email.text,
        phone: _phone.text,
        department: _department,
        jobTitle: _role.text,
        location: _location ?? 'US',
        status: _status,
        employmentType: _employmentType,
      );
      await repo.saveMilestones(profileId: widget.employee.profileId, dob: _dob, joining: _joining);
      _invalidate(ref, widget.employee.id);
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
        _busy = false;
        _error = 'Failed: $e';
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Employee', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
          const SizedBox(height: 10),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 10),
          TextField(controller: _role, decoration: const InputDecoration(labelText: 'Role')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _department,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [for (final d in kEmpDepartments) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _department = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _location,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Location'),
                items: [for (final l in kEmpLocations) DropdownMenuItem(value: l.$1, child: Text(l.$2, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _location = v),
              ),
            ),
          ],),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [for (final s in kEmpStatuses) DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1)))],
            onChanged: (v) => setState(() => _status = v ?? 'active'),
          ),
          const SizedBox(height: 10),
          // Employment Type (web EditEmployeeDialog: Full-Time/Probation/Intern).
          DropdownButtonFormField<String>(
            initialValue: _employmentType,
            decoration: const InputDecoration(labelText: 'Employment Type'),
            items: [
              for (final t in kEmploymentTypes)
                DropdownMenuItem(value: t, child: Text(kEmploymentTypeLabels[t]!)),
            ],
            onChanged: (v) => setState(() => _employmentType = v ?? 'full_time'),
          ),
          const SizedBox(height: 12),
          Text('Milestones', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _dateField(context, 'Birthday', _dob, (s) => setState(() => _dob = s))),
            const SizedBox(width: 12),
            Expanded(child: _dateField(context, 'Work Anniversary', _joining, (s) => setState(() => _joining = s))),
          ],),
          if (widget.employee.profileId == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text("This employee hasn't signed up yet, so milestones can't be saved until their profile exists.",
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            ),
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
                  : const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateField(BuildContext context, String label, String? value, ValueChanged<String> onPick) => InkWell(
        onTap: () async {
          final init = value != null ? DateTime.tryParse(value) ?? DateTime(2000) : DateTime(2000);
          final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(1950), lastDate: DateTime(DateTime.now().year + 1));
          if (d != null) onPick('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
        },
        child: InputDecorator(decoration: InputDecoration(labelText: label), child: Text(value ?? 'Not set')),
      );
}
