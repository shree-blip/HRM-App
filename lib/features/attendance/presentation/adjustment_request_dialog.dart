import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/attendance_time.dart';
import '../data/attendance_models.dart';
import '../data/attendance_providers.dart';

/// Employee-initiated attendance correction request. Proposes new clock in/out
/// and — like the web AdjustmentRequestDialog — shows the log's actual break/
/// pause sessions as editable start/end rows; the proposed break/pause minute
/// totals are derived from those sessions. Sessions themselves are read-only
/// (only the proposed totals are submitted). No schema change.
Future<bool?> showAdjustmentRequestDialog(
  BuildContext context,
  WidgetRef ref,
  AttendanceLog log,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _AdjustmentDialog(log: log),
  );
}

/// One editable session row (NPT wall-clock times).
class _EditableSession {
  _EditableSession({required this.type, required this.start, this.end});
  final String type; // break | pause
  DateTime start;
  DateTime? end;

  int get minutes {
    if (end == null) return 0;
    final m = end!.difference(start).inMinutes;
    return m > 0 ? m : 0;
  }
}

class _AdjustmentDialogState extends ConsumerState<_AdjustmentDialog> {
  late DateTime _clockInNpt; // NPT wall-clock components
  late DateTime _clockOutNpt;
  final List<_EditableSession> _sessions = [];
  bool _sessionsLoading = true;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _off = NptTime.offset;

  @override
  void initState() {
    super.initState();
    _clockInNpt = widget.log.clockIn.add(_off);
    _clockOutNpt = (widget.log.clockOut ?? DateTime.now().toUtc()).add(_off);
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final rows = await ref
          .read(attendanceRepositoryProvider)
          .breakSessions(widget.log.id);
      for (final s in rows) {
        _sessions.add(_EditableSession(
          type: s.sessionType,
          start: s.startTime.add(_off),
          end: s.endTime?.add(_off),
        ),);
      }
    } catch (_) {}
    // Legacy fallback — synthesize rows from the single-record fields when no
    // per-session rows exist (mirrors the web dialog).
    if (_sessions.isEmpty) {
      final log = widget.log;
      if (log.breakStart != null && log.totalBreakMinutes > 0) {
        _sessions.add(_EditableSession(
          type: 'break',
          start: log.breakStart!.add(_off),
          end: log.breakEnd?.add(_off),
        ),);
      }
      if (log.pauseStart != null && log.totalPauseMinutes > 0) {
        _sessions.add(_EditableSession(
          type: 'pause',
          start: log.pauseStart!.add(_off),
          end: log.pauseEnd?.add(_off),
        ),);
      }
    }
    if (mounted) setState(() => _sessionsLoading = false);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _breakTotal =>
      _sessions.where((s) => s.type == 'break').fold(0, (a, s) => a + s.minutes);
  int get _pauseTotal =>
      _sessions.where((s) => s.type == 'pause').fold(0, (a, s) => a + s.minutes);

  String _fmt(DateTime nptWall) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    var h = nptWall.hour % 12;
    if (h == 0) h = 12;
    final ap = nptWall.hour < 12 ? 'AM' : 'PM';
    return '${months[nptWall.month - 1]} ${nptWall.day}, '
        '$h:${nptWall.minute.toString().padLeft(2, '0')} $ap';
  }

  String _fmtTime(DateTime? nptWall) {
    if (nptWall == null) return 'ongoing';
    var h = nptWall.hour % 12;
    if (h == 0) h = 12;
    final ap = nptWall.hour < 12 ? 'AM' : 'PM';
    return '$h:${nptWall.minute.toString().padLeft(2, '0')} $ap';
  }

  Future<DateTime?> _pickDateTime(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 1),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null) return null;
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pick(bool isIn) async {
    final picked = await _pickDateTime(isIn ? _clockInNpt : _clockOutNpt);
    if (picked == null) return;
    setState(() {
      if (isIn) {
        _clockInNpt = picked;
      } else {
        _clockOutNpt = picked;
      }
    });
  }

  Future<void> _pickSession(_EditableSession s, bool isStart) async {
    final picked =
        await _pickDateTime(isStart ? s.start : (s.end ?? s.start));
    if (picked == null) return;
    setState(() {
      if (isStart) {
        s.start = picked;
      } else {
        s.end = picked;
      }
    });
  }

  // NPT wall-clock components -> the matching UTC instant.
  DateTime _toUtc(DateTime nptWall) => DateTime.utc(
        nptWall.year, nptWall.month, nptWall.day, nptWall.hour, nptWall.minute,
      ).subtract(_off);

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Please enter a reason for the adjustment.');
      return;
    }
    final inUtc = _toUtc(_clockInNpt);
    final outUtc = _toUtc(_clockOutNpt);
    if (!outUtc.isAfter(inUtc)) {
      setState(() => _error = 'Clock-out must be after clock-in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(attendanceRepositoryProvider).submitAdjustment(
            logId: widget.log.id,
            originalClockIn: widget.log.clockIn,
            originalClockOut: widget.log.clockOut,
            originalBreakMinutes: widget.log.totalBreakMinutes,
            originalPauseMinutes: widget.log.totalPauseMinutes,
            proposedClockIn: inUtc,
            proposedClockOut: outUtc,
            proposedBreakMinutes: _breakTotal,
            proposedPauseMinutes: _pauseTotal,
            reason: reason,
          );
      ref.invalidate(myAdjustmentsProvider);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Request Adjustment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For ${NptTime.formatDateShort(widget.log.clockIn)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
            const SizedBox(height: 12),
            _timeRow('Proposed clock-in', _fmt(_clockInNpt), () => _pick(true)),
            const SizedBox(height: 8),
            _timeRow('Proposed clock-out', _fmt(_clockOutNpt), () => _pick(false)),
            const SizedBox(height: 12),
            // ── Break & Pause sessions (web parity) ──
            Row(
              children: [
                Expanded(
                  child: Text('BREAK & PAUSE SESSIONS',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,),),
                ),
                Text('${_breakTotal}m break · ${_pauseTotal}m pause',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),),
              ],
            ),
            const SizedBox(height: 6),
            if (_sessionsLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),),
                ),
              )
            else if (_sessions.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('No break or pause sessions recorded for this log.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              )
            else
              Column(children: [for (final s in _sessions) _sessionRow(s)]),
            if (!_sessionsLoading && _sessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "Tap a session's start/end to correct it — totals recalculate automatically.",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                hintText: 'e.g., Forgot to end break, actual break ended at 1:30 PM',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
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
              : const Text('Submit'),
        ),
      ],
    );
  }

  Widget _sessionRow(_EditableSession s) {
    final theme = Theme.of(context);
    final isBreak = s.type == 'break';
    final color = isBreak ? Colors.orange.shade800 : Colors.blue.shade700;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isBreak ? Icons.coffee_outlined : Icons.pause_circle_outline,
              size: 16, color: color,),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(isBreak ? 'Break' : 'Pause',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: color,),),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                InkWell(
                  onTap: () => _pickSession(s, true),
                  child: Text(_fmtTime(s.start),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,),),
                ),
                const Text(' → '),
                InkWell(
                  onTap: () => _pickSession(s, false),
                  child: Text(_fmtTime(s.end),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,),),
                ),
              ],
            ),
          ),
          Text('${s.minutes}m',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),),
        ],
      ),
    );
  }

  Widget _timeRow(String label, String value, VoidCallback onEdit) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600),),
            ],
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: const Text('Change'),
          onPressed: onEdit,
        ),
      ],
    );
  }
}

class _AdjustmentDialog extends ConsumerStatefulWidget {
  const _AdjustmentDialog({required this.log});
  final AttendanceLog log;

  @override
  ConsumerState<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}
