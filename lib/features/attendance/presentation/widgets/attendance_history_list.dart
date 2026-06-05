import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/attendance_time.dart';
import '../../data/attendance_models.dart';
import '../../data/attendance_providers.dart';

/// "My Attendance History" — this month's logs, newest first, with an
/// expandable break/pause breakdown per day.
class AttendanceHistoryList extends ConsumerWidget {
  const AttendanceHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceHistoryProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Could not load attendance history.'),
      ),
      data: (logs) {
        if (logs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No attendance records this month.')),
          );
        }
        return Column(
          children: [for (final l in logs) _HistoryTile(log: l)],
        );
      },
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.log});
  final AttendanceLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final net = log.netHours();
    final hoursText =
        net == net.roundToDouble() ? '${net.toInt()}h' : '${net.toStringAsFixed(1)}h';
    final range =
        '${NptTime.formatTime(log.clockIn)} → ${log.clockOut != null ? NptTime.formatTime(log.clockOut!) : 'now'}';
    final totalBreaks = log.totalBreakMinutes + log.totalPauseMinutes;

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(NptTime.formatDateShort(log.clockIn),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),),
            ),
            Text(hoursText,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold),),
            if (log.isEdited)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.edit_note,
                    size: 16, color: theme.colorScheme.onSurfaceVariant,),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(range, style: theme.textTheme.bodySmall),
              ),
              _MiniStatus(log: log),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Breaks + pauses',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
              Text(formatDurationMinutes(totalBreaks),
                  style: theme.textTheme.bodySmall,),
            ],
          ),
          if (log.clockType != null || log.workMode != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Type / mode',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,),),
                  Text(
                    '${log.clockType ?? '—'} · ${log.workMode?.toUpperCase() ?? '—'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          _SessionList(logId: log.id),
        ],
      ),
    );
  }
}

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.logId});
  final String logId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_breakSessionsProvider(logId));
    final theme = Theme.of(context);
    return async.when(
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text('No break/pause sessions.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),),
          );
        }
        return Column(
          children: [
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(s.isBreak ? Icons.coffee_outlined : Icons.pause,
                        size: 16, color: theme.colorScheme.onSurfaceVariant,),
                    const SizedBox(width: 8),
                    Text(s.isBreak ? 'Break' : 'Pause',
                        style: theme.textTheme.bodySmall,),
                    const Spacer(),
                    Text(
                      '${NptTime.formatTime(s.startTime)}'
                      '${s.endTime != null ? ' – ${NptTime.formatTime(s.endTime!)}' : ' – ongoing'}'
                      '  (${formatDurationMinutes(s.durationMinutes ?? 0)})',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

final _breakSessionsProvider =
    FutureProvider.autoDispose.family<List<BreakSession>, String>(
  (ref, logId) =>
      ref.read(attendanceRepositoryProvider).breakSessions(logId),
);

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.log});
  final AttendanceLog log;

  @override
  Widget build(BuildContext context) {
    final s = log.status ?? (log.clockOut != null ? 'completed' : 'active');
    final (bg, fg) = switch (s) {
      'auto_clocked_out' => (const Color(0xFFFEF3C7), const Color(0xFFD97706)),
      'completed' => (const Color(0xFFE5E7EB), const Color(0xFF6B7280)),
      _ => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.replaceAll('_', ' '),
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),),
    );
  }
}
