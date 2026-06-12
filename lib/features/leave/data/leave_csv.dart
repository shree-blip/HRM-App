import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'leave_models.dart';

String _esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';

/// My-leave history CSV — exact columns of the web exportLeaveHistoryToCsv.
String leaveHistoryCsv(List<LeaveRequest> requests) {
  const headers = [
    'Leave Type', 'Start Date', 'End Date', 'Days', 'Status', 'Reason',
    'Rejection Reason',
  ];
  final rows = requests.map((r) => [
        _esc(r.leaveType),
        _esc(r.startDate),
        _esc(r.endDate),
        _esc(r.days),
        _esc(r.status),
        _esc(r.reason ?? ''),
        _esc(r.rejectionReason ?? ''),
      ].join(','),);
  return [headers.map(_esc).join(','), ...rows].join('\n');
}

/// Approvals CSV — exact columns of the web Approvals exportCSV.
String leaveApprovalsCsv(List<LeaveRequest> requests) {
  const headers = [
    'Employee', 'Email', 'Leave Type', 'Start Date', 'End Date', 'Days',
    'Status', 'Reason', 'Rejection Reason',
  ];
  final rows = requests.map((r) => [
        _esc(r.employeeName ?? 'Unknown'),
        _esc(r.employeeEmail ?? ''),
        _esc(r.leaveType),
        _esc(r.startDate),
        _esc(r.endDate),
        _esc(r.days),
        _esc(r.status),
        _esc(r.reason ?? ''),
        _esc(r.rejectionReason ?? ''),
      ].join(','),);
  return [headers.map(_esc).join(','), ...rows].join('\n');
}

/// Write [content] to a temp .csv and open the native share sheet.
Future<void> shareCsv(String fileName, String content) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName.csv');
  await file.writeAsString(content);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv')],
    subject: fileName,
  );
}
