import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/attendance_providers.dart';

/// Generates an attendance CSV for [timeframe] (today | week | month) and opens
/// the native share sheet. Shared by the Live Attendance card and the
/// Attendance screen so the export behaves identically everywhere.
Future<void> exportAttendanceCsv(
  BuildContext context,
  WidgetRef ref,
  String timeframe, {
  DateTime? customStart,
  DateTime? customEnd,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final label = timeframe == 'custom' ? 'custom range' : timeframe;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text('Preparing $label export…')));
  try {
    final csv = await ref.read(liveAttendanceRepositoryProvider).attendanceCsv(
          timeframe,
          customStart: customStart,
          customEnd: customEnd,
        );
    final rowCount = '\n'.allMatches(csv).length; // minus header
    if (rowCount <= 0) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('No attendance data for $label.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/attendance_$timeframe.csv');
    await file.writeAsString(csv);
    messenger.clearSnackBars();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Attendance ($label)',
      text: 'Attendance export — $label ($rowCount rows)',
    );
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

/// Prompt for a date range, then export. Mirrors the web Attendance custom-range
/// export dialog.
Future<void> exportAttendanceCustomRange(
  BuildContext context,
  WidgetRef ref,
) async {
  final now = DateTime.now();
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 1),
    initialDateRange: DateTimeRange(
      start: now.subtract(const Duration(days: 6)),
      end: now,
    ),
  );
  if (range == null || !context.mounted) return;
  await exportAttendanceCsv(
    context,
    ref,
    'custom',
    customStart: range.start,
    customEnd: range.end,
  );
}

const List<({String value, String label})> kExportTimeframes = [
  (value: 'today', label: "Today's data"),
  (value: 'week', label: "This week's data"),
  (value: 'month', label: "This month's data"),
  (value: 'custom', label: 'Custom range…'),
];
