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
  String timeframe,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text('Preparing $timeframe export…')));
  try {
    final csv =
        await ref.read(liveAttendanceRepositoryProvider).attendanceCsv(timeframe);
    final rowCount = '\n'.allMatches(csv).length; // minus header
    if (rowCount <= 0) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('No attendance data for $timeframe.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/attendance_$timeframe.csv');
    await file.writeAsString(csv);
    messenger.clearSnackBars();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Attendance ($timeframe)',
      text: 'Attendance export — $timeframe ($rowCount rows)',
    );
  } catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

const List<({String value, String label})> kExportTimeframes = [
  (value: 'today', label: "Today's data"),
  (value: 'week', label: "This week's data"),
  (value: 'month', label: "This month's data"),
];
