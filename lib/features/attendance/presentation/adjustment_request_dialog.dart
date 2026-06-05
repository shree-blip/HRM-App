import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/attendance_time.dart';
import '../data/attendance_models.dart';
import '../data/attendance_providers.dart';

/// Employee-initiated attendance correction request (feature B). Proposes new
/// clock in/out + break/pause minutes with a required reason; writes to
/// attendance_adjustment_requests and notifies the manager. No schema change.
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

class _AdjustmentDialog extends ConsumerStatefulWidget {
  const _AdjustmentDialog({required this.log});
  final AttendanceLog log;

  @override
  ConsumerState<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends ConsumerState<_AdjustmentDialog> {
  late DateTime _clockInNpt; // NPT wall-clock components
  late DateTime _clockOutNpt;
  late final TextEditingController _break;
  late final TextEditingController _pause;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _off = NptTime.offset;

  @override
  void initState() {
    super.initState();
    _clockInNpt = widget.log.clockIn.add(_off);
    _clockOutNpt = (widget.log.clockOut ?? DateTime.now().toUtc()).add(_off);
    _break = TextEditingController(text: '${widget.log.totalBreakMinutes}');
    _pause = TextEditingController(text: '${widget.log.totalPauseMinutes}');
  }

  @override
  void dispose() {
    _break.dispose();
    _pause.dispose();
    _reason.dispose();
    super.dispose();
  }

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

  Future<void> _pick(bool isIn) async {
    final current = isIn ? _clockInNpt : _clockOutNpt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 1),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null) return;
    final picked = DateTime.utc(
      date.year, date.month, date.day, time.hour, time.minute,
    );
    setState(() {
      if (isIn) {
        _clockInNpt = picked;
      } else {
        _clockOutNpt = picked;
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
            proposedBreakMinutes: int.tryParse(_break.text.trim()) ?? 0,
            proposedPauseMinutes: int.tryParse(_pause.text.trim()) ?? 0,
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _break,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Break (min)', isDense: true,),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pause,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pause (min)', isDense: true,),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                hintText: 'Why does this need correcting?',
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
