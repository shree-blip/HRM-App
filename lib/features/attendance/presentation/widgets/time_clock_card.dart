import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/attendance_time.dart';
import '../../data/attendance_models.dart';
import '../../data/attendance_providers.dart';

/// The clock-in/out widget. Server-authoritative: every action calls the
/// edge function and the resulting log drives the UI. Shared by the dashboard
/// and the Attendance screen.
class TimeClockCard extends ConsumerStatefulWidget {
  const TimeClockCard({super.key});

  @override
  ConsumerState<TimeClockCard> createState() => _TimeClockCardState();
}

class _TimeClockCardState extends ConsumerState<TimeClockCard> {
  Timer? _ticker;
  String _clockType = 'payroll';

  @override
  void initState() {
    super.initState();
    // 1s tick so the live elapsed timer updates while active.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = ref.watch(timeTrackerProvider);
    final stats = ref.watch(attendanceStatsProvider).valueOrNull;
    final notifier = ref.read(timeTrackerProvider.notifier);
    final status = st.status;
    final log = st.openLog;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time_filled, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Time Clock',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),),
                const Spacer(),
                _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 12),

            if (st.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Center(
                child: Column(
                  children: [
                    Text(
                      log == null
                          ? '--:--:--'
                          : formatHms(log.netElapsed(DateTime.now().toUtc())),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (log != null)
                      Text(
                        '${status == ClockStatus.paused ? 'Paused' : status == ClockStatus.onBreak ? 'On break' : 'Clocked in'} · since ${NptTime.formatTime(log.clockIn)}'
                        '${log.workMode != null ? ' · ${log.workMode!.toUpperCase()}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildActions(context, status, st.busy, notifier),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _Summary(stats: stats),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    ClockStatus status,
    bool busy,
    TimeTrackerController notifier,
  ) {
    if (busy) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    switch (status) {
      case ClockStatus.out:
        return Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'payroll', label: Text('Payroll')),
                ButtonSegment(value: 'billable', label: Text('Billable')),
              ],
              selected: {_clockType},
              onSelectionChanged: (s) => setState(() => _clockType = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.business),
                    label: const Text('Clock In · Office'),
                    onPressed: () => _guard(() => notifier.clockIn(
                          clockType: _clockType,
                          workMode: 'wfo',
                        ),),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Clock In · Home'),
                    onPressed: () => _guard(() => notifier.clockIn(
                          clockType: _clockType,
                          workMode: 'wfh',
                        ),),
                  ),
                ),
              ],
            ),
          ],
        );

      case ClockStatus.active:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.coffee_outlined),
                label: const Text('Break'),
                onPressed: () => _guard(notifier.startBreak),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
                onPressed: () => _guard(notifier.startPause),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Out'),
                onPressed: () => _confirmClockOut(notifier),
              ),
            ),
          ],
        );

      case ClockStatus.onBreak:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
                onPressed: () => _guard(notifier.endBreak),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Clock Out'),
                onPressed: () => _confirmClockOut(notifier),
              ),
            ),
          ],
        );

      case ClockStatus.paused:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
                onPressed: () => _resumeFromPause(notifier),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Clock Out'),
                onPressed: () => _confirmClockOut(notifier),
              ),
            ),
          ],
        );
    }
  }

  Future<void> _confirmClockOut(TimeTrackerController notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clock out?'),
        content: const Text(
          'This ends your shift. For a short break use Break or Pause instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clock Out'),
          ),
        ],
      ),
    );
    if (ok == true) await _guard(notifier.clockOut);
  }

  Future<void> _resumeFromPause(TimeTrackerController notifier) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Where are you working from?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'wfo'),
            child: const Text('Office'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'wfh'),
            child: const Text('Home'),
          ),
        ],
      ),
    );
    if (mode != null) await _guard(() => notifier.endPause(newWorkMode: mode));
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ClockStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      ClockStatus.active => ('Active', const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      ClockStatus.onBreak => ('On Break', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      ClockStatus.paused => ('Paused', const Color(0xFFE0E7FF), const Color(0xFF4F46E5)),
      ClockStatus.out => ('Not Clocked In', const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({this.stats});
  final AttendanceStats? stats;

  @override
  Widget build(BuildContext context) {
    String h(double? v) =>
        v == null ? '—' : (v == v.roundToDouble() ? '${v.toInt()}h' : '${v.toStringAsFixed(1)}h');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _cell(context, 'Today', h(stats?.today)),
        _cell(context, 'Week', h(stats?.week)),
        _cell(context, 'Month', h(stats?.month)),
      ],
    );
  }

  Widget _cell(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
      ],
    );
  }
}
