import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/document_models.dart';
import '../data/documents_providers.dart';
import '../data/documents_repository.dart';
import '../data/drive_links.dart';

/// "Add Document Link" — bulk, per-category Drive-link form (ports the web
/// UploadDocumentDialog). Contracts→VP only; everyone gets Policies/Compliance/
/// Leave Evidence. Saves via createDriveDocumentsBulk.
Future<bool?> showDocumentForm(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _DocumentForm(),
    ),
  );
}

class _LinkRow {
  _LinkRow({String name = '', String link = ''})
      : name = TextEditingController(text: name),
        link = TextEditingController(text: link);
  final TextEditingController name;
  final TextEditingController link;
  void dispose() {
    name.dispose();
    link.dispose();
  }
}

class _DocumentForm extends ConsumerStatefulWidget {
  const _DocumentForm();
  @override
  ConsumerState<_DocumentForm> createState() => _DocumentFormState();
}

class _DocumentFormState extends ConsumerState<_DocumentForm> {
  String? _category;
  bool _busy = false;
  String? _error;
  String? _myEmployeeId;

  // Contracts
  String? _contractEmployeeId;
  final _contractName = TextEditingController();
  final _contractLink = TextEditingController();

  // Policies (bulk)
  final List<_LinkRow> _policyRows = [_LinkRow()];

  // Compliance
  final Set<String> _complianceEmployeeIds = {};
  final Map<String, _LinkRow> _complianceByEmp = {};
  final List<_LinkRow> _complianceRows = [_LinkRow()];
  String _empSearch = '';

  // Leave Evidence
  final _leaveName = TextEditingController();
  final _leaveLink = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.read(documentsRepositoryProvider).myEmployeeId().then((id) {
      if (mounted) _myEmployeeId = id;
    });
  }

  @override
  void dispose() {
    _contractName.dispose();
    _contractLink.dispose();
    _leaveName.dispose();
    _leaveLink.dispose();
    for (final r in _policyRows) {
      r.dispose();
    }
    for (final r in _complianceRows) {
      r.dispose();
    }
    for (final r in _complianceByEmp.values) {
      r.dispose();
    }
    super.dispose();
  }

  bool get _managerOrAbove => isManagerOrAbove(ref);

  List<DriveDocItem>? _buildItems() {
    List<DriveDocItem>? err(String m) {
      setState(() => _error = m);
      return null;
    }

    switch (_category) {
      case 'Contracts':
        if (_contractEmployeeId == null) return err('Select an employee.');
        if (_contractName.text.trim().isEmpty) return err('Enter a contract name.');
        if (!isValidDriveLink(_contractLink.text)) return err('Enter a valid Google Drive link.');
        return [
          DriveDocItem(
            name: _contractName.text.trim(),
            category: 'Contracts',
            driveLink: _contractLink.text.trim(),
            employeeId: _contractEmployeeId,
          ),
        ];
      case 'Policies':
        final valid = _policyRows.where((r) => r.name.text.trim().isNotEmpty && r.link.text.trim().isNotEmpty).toList();
        if (valid.isEmpty) return err('Add at least one policy name and link.');
        for (final r in valid) {
          if (!isValidDriveLink(r.link.text)) return err('"${r.name.text.trim()}" has an invalid Drive link.');
        }
        return [
          for (final r in valid)
            DriveDocItem(name: r.name.text.trim(), category: 'Policies', driveLink: r.link.text.trim()),
        ];
      case 'Compliance':
        if (_managerOrAbove) {
          if (_complianceEmployeeIds.isEmpty) return err('Select at least one employee.');
          final items = <DriveDocItem>[];
          for (final empId in _complianceEmployeeIds) {
            final row = _complianceByEmp[empId];
            final name = row?.name.text.trim() ?? '';
            final link = row?.link.text.trim() ?? '';
            if (name.isEmpty || link.isEmpty) return err('Enter a document name and link for each selected employee.');
            if (!isValidDriveLink(link)) return err('An invalid Drive link was entered.');
            items.add(DriveDocItem(name: name, category: 'Compliance', driveLink: link, employeeId: empId));
          }
          return items;
        }
        final valid = _complianceRows.where((r) => r.name.text.trim().isNotEmpty && r.link.text.trim().isNotEmpty).toList();
        if (valid.isEmpty) return err('Add at least one document name and link.');
        for (final r in valid) {
          if (!isValidDriveLink(r.link.text)) return err('"${r.name.text.trim()}" has an invalid Drive link.');
        }
        if (_myEmployeeId == null) return err('No employee record found.');
        return [
          for (final r in valid)
            DriveDocItem(name: r.name.text.trim(), category: 'Compliance', driveLink: r.link.text.trim(), employeeId: _myEmployeeId),
        ];
      case 'Leave Evidence':
        if (_leaveName.text.trim().isEmpty) return err('Enter a document name.');
        if (!isValidDriveLink(_leaveLink.text)) return err('Enter a valid Google Drive link.');
        return [
          DriveDocItem(
            name: _leaveName.text.trim(),
            category: 'Leave Evidence',
            driveLink: _leaveLink.text.trim(),
            employeeId: _myEmployeeId,
          ),
        ];
      default:
        return err('Select a category.');
    }
  }

  Future<void> _submit() async {
    final items = _buildItems();
    if (items == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      // managerUpload mirrors the web's isManagerUploadingForEmployee flag
      // (manager-or-above uploading a doc assigned to an employee).
      await ref.read(documentsRepositoryProvider).createDriveDocumentsBulk(
            items,
            managerUpload:
                _managerOrAbove && items.any((i) => i.employeeId != null),
          );
      ref.invalidate(documentsProvider);
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
    final cats = allowedAddCategories(ref);
    final employees = ref.watch(documentsEmployeesProvider).valueOrNull ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Document Link', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Save a Google Drive link and document details.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Document category *'),
            items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v),
          ),
          if (_category != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(categoryInfo(_category!), style: theme.textTheme.bodySmall)),
              ],),
            ),
          ],
          const SizedBox(height: 12),
          if (_category == 'Contracts') _contractsSection(employees),
          if (_category == 'Policies') _rowsSection(_policyRows, 'Policy', 'Add another policy'),
          if (_category == 'Compliance') _complianceSection(employees),
          if (_category == 'Leave Evidence') _leaveSection(),
          if (_category != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(kDriveLinkHelperText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || _category == null ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Link'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contractsSection(List<DocEmployee> employees) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _contractEmployeeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Select employee *'),
            items: [for (final e in employees) DropdownMenuItem(value: e.id, child: Text(e.label, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _contractEmployeeId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _contractName, decoration: const InputDecoration(labelText: 'Contract name *')),
          const SizedBox(height: 10),
          TextField(controller: _contractLink, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Google Drive link *', prefixIcon: Icon(Icons.link, size: 18))),
        ],
      );

  Widget _rowsSection(List<_LinkRow> rows, String label, String addText) => StatefulBuilder(
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(children: [
                      Text('$label ${i + 1}', style: Theme.of(context).textTheme.labelSmall),
                      const Spacer(),
                      if (rows.length > 1)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => rows.removeAt(i).dispose()),
                        ),
                    ],),
                    TextField(controller: rows[i].name, decoration: InputDecoration(labelText: '$label name')),
                    const SizedBox(height: 6),
                    TextField(controller: rows[i].link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'https://drive.google.com/…')),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: Text(addText),
                onPressed: () => setState(() => rows.add(_LinkRow())),
              ),
            ),
          ],
        ),
      );

  Widget _complianceSection(List<DocEmployee> employees) {
    if (!_managerOrAbove) {
      return _rowsSection(_complianceRows, 'Document', 'Add another link');
    }
    final filtered = employees
        .where((e) => e.label.toLowerCase().contains(_empSearch.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select employees *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search employees…'),
          onChanged: (v) => setState(() => _empSearch = v),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in filtered)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _complianceEmployeeIds.contains(e.id),
                  title: Text(e.label),
                  onChanged: (_) => setState(() {
                    if (_complianceEmployeeIds.contains(e.id)) {
                      _complianceEmployeeIds.remove(e.id);
                      _complianceByEmp.remove(e.id)?.dispose();
                    } else {
                      _complianceEmployeeIds.add(e.id);
                      _complianceByEmp[e.id] = _LinkRow();
                    }
                  }),
                ),
              if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No employees found')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_complianceEmployeeIds.isEmpty)
          Text('Select employees above to add a document for each.', style: Theme.of(context).textTheme.bodySmall)
        else
          for (final empId in _complianceEmployeeIds)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(employees.firstWhere((e) => e.id == empId, orElse: () => const DocEmployee(id: '', name: 'Employee')).label,
                        style: Theme.of(context).textTheme.labelSmall,),
                  ),
                  TextField(controller: _complianceByEmp[empId]!.name, decoration: const InputDecoration(labelText: 'Document name')),
                  const SizedBox(height: 6),
                  TextField(controller: _complianceByEmp[empId]!.link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'https://drive.google.com/…')),
                ],
              ),
            ),
      ],
    );
  }

  Widget _leaveSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: _leaveName, decoration: const InputDecoration(labelText: 'Document name *')),
          const SizedBox(height: 10),
          TextField(controller: _leaveLink, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Google Drive link *', prefixIcon: Icon(Icons.link, size: 18))),
        ],
      );
}
