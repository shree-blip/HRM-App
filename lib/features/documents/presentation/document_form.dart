import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../data/document_models.dart';
import '../data/documents_providers.dart';

/// Categories the current user is allowed to add (mirrors web upload rules).
List<String> allowedAddCategories(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  final canManage = auth.isAdmin ||
      auth.isVp ||
      auth.isManager ||
      auth.isLineManager ||
      ref.read(permissionsControllerProvider).has(Permission.manageDocuments);
  return [
    if (auth.isVp || auth.isAdmin) 'Contracts',
    if (canManage) 'Policies',
    if (canManage) 'Compliance',
    'Leave Evidence', // any employee
  ];
}

Future<bool?> showDocumentForm(BuildContext context, {HrDocument? existing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DocumentForm(existing: existing),
    ),
  );
}

class _DocumentForm extends ConsumerStatefulWidget {
  const _DocumentForm({this.existing});
  final HrDocument? existing;

  @override
  ConsumerState<_DocumentForm> createState() => _DocumentFormState();
}

class _DocumentFormState extends ConsumerState<_DocumentForm> {
  late final TextEditingController _title;
  late final TextEditingController _url;
  String? _category;
  String _type = 'link';
  String? _employeeId;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _title = TextEditingController(text: d?.name ?? '');
    _url = TextEditingController(text: d != null && d.isLink ? d.filePath : '');
    _category = d?.category;
    _type = d?.fileType ?? 'link';
    _employeeId = d?.employeeId;
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (_category == null) {
      setState(() => _error = 'Pick a category.');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = 'Enter a valid Google Drive link (https://…).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(documentsRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateDocument(
          widget.existing!.id,
          name: _title.text,
          driveUrl: url,
          fileType: _type,
          category: _category,
          employeeId: _employeeId,
        );
      } else {
        await repo.addDocument(
          name: _title.text,
          driveUrl: url,
          category: _category!,
          fileType: _type,
          employeeId: _employeeId,
        );
      }
      ref.invalidate(documentsProvider);
      if (mounted) Navigator.of(context).pop(true);
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
    // For edit, ensure the doc's category is selectable even if role changed.
    final catOptions = {
      ...cats,
      if (_category != null) _category!,
    }.toList();
    final needsAssignee = _category == 'Contracts' || _category == 'Compliance';
    final employees = ref.watch(documentsEmployeesProvider).valueOrNull ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEdit ? 'Edit document' : 'Add document', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Add a Google Drive link (file upload coming later).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: catOptions.contains(_category) ? _category : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category *'),
            items: [
              for (final c in catOptions) DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in kDocTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2)),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'link'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Google Drive link *',
              hintText: 'https://drive.google.com/…',
              prefixIcon: Icon(Icons.link, size: 18),
            ),
          ),
          if (needsAssignee) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: employees.any((e) => e.id == _employeeId) ? _employeeId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Assign to employee (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No specific employee')),
                for (final e in employees)
                  DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _employeeId = v),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),)
                  : Text(_isEdit ? 'Save changes' : 'Add document'),
            ),
          ),
        ],
      ),
    );
  }
}
