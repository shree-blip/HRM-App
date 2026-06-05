import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/attendance_time.dart';
import '../data/reports_models.dart';
import '../data/reports_providers.dart';

/// Direct Edit Attendance (ports the web EditAttendanceDialog): edit clock
/// in/out + break/pause sessions with a required reason, or delete the record.
/// Writes via apply_attendance_edit + attendance_edit_logs + VP notifications.
class EditAttendanceScreen extends ConsumerStatefulWidget {
  const EditAttendanceScreen({super.key, required this.record});
  final DailyRecord record;

  @override
  ConsumerState<EditAttendanceScreen> createState() => _EditAttendanceScreenState();
}

class _SessionRow {
  _SessionRow({this.dbId, required this.type, this.start, this.end}) : deleted = false;
  final String? dbId;
  final String type; // break | pause
  DateTime? start; // NPT wall-clock
  DateTime? end;
  bool deleted;

  int get minutes {
    if (start == null || end == null) return 0;
    final m = end!.difference(start!).inMinutes;
    return m > 0 ? m : 0;
  }
}

class _EditAttendanceScreenState extends ConsumerState<EditAttendanceScreen> {
  static const _off = NptTime.offset;
  late DateTime _clockIn;
  DateTime? _clockOut;
  final _reason = TextEditingController();
  final List<_SessionRow> _sessions = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clockIn = widget.record.clockIn.add(_off);
    _clockOut = widget.record.clockOut?.add(_off);
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(reportsRepositoryProvider).sessions(widget.record.id);
      for (final s in rows) {
        _sessions.add(_SessionRow(
          dbId: s.dbId,
          type: s.type,
          start: s.start.add(_off),
          end: s.end?.add(_off),
        ),);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _fmt(DateTime? npt) {
    if (npt == null) return 'Not set';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    var h = npt.hour % 12;
    if (h == 0) h = 12;
    final ap = npt.hour < 12 ? 'AM' : 'PM';
    return '${months[npt.month - 1]} ${npt.day}, $h:${npt.minute.toString().padLeft(2, '0')} $ap';
  }

  String? _toUtcIso(DateTime? npt) => npt == null
      ? null
      : DateTime.utc(npt.year, npt.month, npt.day, npt.hour, npt.minute)
          .subtract(_off)
          .toIso8601String();

  Future<DateTime?> _pick(DateTime? initial) async {
    final base = initial ?? _clockIn;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 1),
      lastDate: DateTime(base.year + 1),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breaks = _sessions.where((s) => !s.deleted && s.type == 'break').toList();
    final pauses = _sessions.where((s) => !s.deleted && s.type == 'pause').toList();

    return Scaffold(
      appBar: AppBar(title: Text('Edit — ${widget.record.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Modify attendance. A reason is required; an audit log is created.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
                const SizedBox(height: 12),
                _timeRow('Clock In', _clockIn, (d) => setState(() => _clockIn = d)),
                const SizedBox(height: 8),
                _timeRow('Clock Out', _clockOut, (d) => setState(() => _clockOut = d),
                    nullable: true,),
                const SizedBox(height: 16),
                _sessionSection('Breaks', 'break', breaks),
                const SizedBox(height: 12),
                _sessionSection('Pauses', 'pause', pauses),
                const SizedBox(height: 16),
                TextField(
                  controller: _reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason for edit *',
                    hintText: 'Why is this record being changed?',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,),
                        onPressed: _busy ? null : _confirmDelete,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),)
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _timeRow(String label, DateTime? value, ValueChanged<DateTime> onPick,
      {bool nullable = false,}) {
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, isDense: true),
            child: Text(_fmt(value)),
          ),
        ),
        TextButton(
          onPressed: () async {
            final d = await _pick(value);
            if (d != null) onPick(d);
          },
          child: const Text('Change'),
        ),
        if (nullable && value != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () => setState(() => _clockOut = null),
          ),
      ],
    );
  }

  Widget _sessionSection(String title, String type, List<_SessionRow> rows) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$title (${rows.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text('Add ${type == 'break' ? 'break' : 'pause'}'),
              onPressed: () => setState(() => _sessions.add(_SessionRow(type: type))),
            ),
          ],
        ),
        if (rows.isEmpty)
          Text('None', style: theme.textTheme.bodySmall),
        for (final s in rows) _sessionRow(s),
      ],
    );
  }

  Widget _sessionRow(_SessionRow s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await _pick(s.start);
                if (d != null) setState(() => s.start = d);
              },
              child: Text(s.start == null ? 'Start' : _fmt(s.start),
                  style: const TextStyle(fontSize: 12),),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await _pick(s.end ?? s.start);
                if (d != null) setState(() => s.end = d);
              },
              child: Text(s.end == null ? 'End' : _fmt(s.end),
                  style: const TextStyle(fontSize: 12),),
            ),
          ),
          const SizedBox(width: 4),
          Text('${s.minutes}m', style: Theme.of(context).textTheme.bodySmall),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: Theme.of(context).colorScheme.error,),
            onPressed: () => setState(() => s.deleted = true),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Please provide a reason for the edit.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final active = _sessions.where((s) => !s.deleted && s.start != null).toList();
      final breaks = active.where((s) => s.type == 'break').toList();
      final pauses = active.where((s) => s.type == 'pause').toList();
      final totalBreak = breaks.fold<int>(0, (a, s) => a + s.minutes);
      final totalPause = pauses.fold<int>(0, (a, s) => a + s.minutes);
      final fb = breaks.isNotEmpty ? breaks.first : null;
      final fp = pauses.isNotEmpty ? pauses.first : null;

      final toDelete =
          _sessions.where((s) => s.deleted && s.dbId != null).map((s) => s.dbId!).toList();
      final toUpdate = _sessions
          .where((s) => !s.deleted && s.dbId != null)
          .map((s) => {
                'id': s.dbId,
                'session_type': s.type,
                'start_time': _toUtcIso(s.start),
                'end_time': _toUtcIso(s.end),
                'duration_minutes': s.minutes > 0 ? s.minutes : null,
              },)
          .toList();
      final toInsert = _sessions
          .where((s) => !s.deleted && s.dbId == null && s.start != null)
          .map((s) => {
                'session_type': s.type,
                'start_time': _toUtcIso(s.start),
                'end_time': _toUtcIso(s.end),
                'duration_minutes': s.minutes > 0 ? s.minutes : null,
              },)
          .toList();

      final clockInIso = _toUtcIso(_clockIn)!;
      final clockOutIso = _toUtcIso(_clockOut);

      await ref.read(reportsRepositoryProvider).applyEdit(
            logId: widget.record.id,
            clockInIso: clockInIso,
            clockOutIso: clockOutIso,
            breakStartIso: fb != null ? _toUtcIso(fb.start) : null,
            breakEndIso: fb != null ? _toUtcIso(fb.end) : null,
            totalBreak: totalBreak,
            pauseStartIso: fp != null ? _toUtcIso(fp.start) : null,
            pauseEndIso: fp != null ? _toUtcIso(fp.end) : null,
            totalPause: totalPause,
            sessionsToDelete: toDelete,
            sessionsToUpdate: toUpdate.cast<Map<String, dynamic>>(),
            sessionsToInsert: toInsert.cast<Map<String, dynamic>>(),
            oldValues: {
              'clock_in': widget.record.clockIn.toIso8601String(),
              'clock_out': widget.record.clockOut?.toIso8601String(),
              'total_break_minutes': widget.record.breakMinutes,
              'total_pause_minutes': widget.record.pauseMinutes,
            },
            newValues: {
              'clock_in': clockInIso,
              'clock_out': clockOutIso,
              'total_break_minutes': totalBreak,
              'total_pause_minutes': totalPause,
            },
            reason: reason,
            employeeName: widget.record.name,
          );
      ref.invalidate(reportDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to save: $e';
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason before deleting.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text('This permanently deletes the attendance record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(reportsRepositoryProvider).deleteRecord(
            logId: widget.record.id,
            oldValues: {
              'clock_in': widget.record.clockIn.toIso8601String(),
              'clock_out': widget.record.clockOut?.toIso8601String(),
              'total_break_minutes': widget.record.breakMinutes,
              'total_pause_minutes': widget.record.pauseMinutes,
            },
            reason: reason,
            employeeName: widget.record.name,
          );
      ref.invalidate(reportDataProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Failed to delete: $e';
        });
      }
    }
  }
}
