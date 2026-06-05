import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/utils/attendance_time.dart';
import 'log_models.dart';
import 'logsheet_repository.dart';

final logSheetRepositoryProvider =
    Provider<LogSheetRepository>((_) => LogSheetRepository());

String _todayKey() => NptTime.nptDateKey(DateTime.now().toUtc());

/// Shared date for My Log + Team Logs (YYYY-MM-DD, NPT).
final selectedLogDateProvider = StateProvider<String>((_) => _todayKey());

final clientsProvider = FutureProvider.autoDispose<List<Client>>(
  (ref) => ref.read(logSheetRepositoryProvider).clients(),
);

final myLogsProvider = FutureProvider.autoDispose<List<WorkLog>>((ref) {
  final date = ref.watch(selectedLogDateProvider);
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(logSheetRepositoryProvider).myLogs(date);
});

final teamLogsProvider = FutureProvider.autoDispose<List<WorkLog>>((ref) {
  final date = ref.watch(selectedLogDateProvider);
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(logSheetRepositoryProvider).teamLogs(date);
});

final liveLogsProvider = FutureProvider.autoDispose<List<WorkLog>>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(logSheetRepositoryProvider).liveLogs(_todayKey());
});

// ── Report tab ──────────────────────────────────────────
class ReportFilter {
  const ReportFilter({
    required this.start,
    required this.end,
    this.clientId,
    this.employeeId,
    this.department,
  });
  final String start;
  final String end;
  final String? clientId;
  final String? employeeId;
  final String? department;

  ReportFilter copyWith({
    String? start,
    String? end,
    Object? clientId = _u,
    Object? employeeId = _u,
    Object? department = _u,
  }) =>
      ReportFilter(
        start: start ?? this.start,
        end: end ?? this.end,
        clientId: clientId == _u ? this.clientId : clientId as String?,
        employeeId: employeeId == _u ? this.employeeId : employeeId as String?,
        department: department == _u ? this.department : department as String?,
      );

  static const _u = Object();
}

String _firstOfMonth() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-01';
}

String _endOfMonth() {
  final n = DateTime.now();
  final last = DateTime(n.year, n.month + 1, 0).day;
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
}

/// The draft filter being edited in the Report tab.
final logReportDraftProvider = StateProvider<ReportFilter>(
  (_) => ReportFilter(start: _firstOfMonth(), end: _endOfMonth()),
);

/// The filter actually applied (set when "Generate Report" is pressed).
/// Null until the user generates → drives the "not searched yet" state.
final appliedReportProvider = StateProvider<ReportFilter?>((_) => null);

/// Employees for the report Employee filter.
final reportEmployeesProvider = FutureProvider.autoDispose<List<LogEmployee>>(
  (ref) => ref.read(logSheetRepositoryProvider).employees(),
);

final logReportProvider = FutureProvider.autoDispose<List<WorkLog>>((ref) {
  final f = ref.watch(appliedReportProvider);
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null || f == null) return Future.value(const []);
  return ref.read(logSheetRepositoryProvider).reportLogs(
        start: f.start,
        end: f.end,
        clientId: f.clientId,
        employeeId: f.employeeId,
        department: f.department,
      );
});
