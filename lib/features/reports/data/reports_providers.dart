import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/team/team_scope.dart';
import 'reports_models.dart';
import 'reports_repository.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((_) => ReportsRepository());

/// Holds the selected report window (preset or custom).
final reportRangeProvider =
    NotifierProvider<ReportRangeController, ReportWindow>(ReportRangeController.new);

class ReportRangeController extends Notifier<ReportWindow> {
  ReportRange _range = ReportRange.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;

  ReportRange get range => _range;

  @override
  ReportWindow build() => ReportWindow.resolve(ReportRange.thisMonth);

  void setPreset(ReportRange r) {
    _range = r;
    state = ReportWindow.resolve(r, customStart: _customStart, customEnd: _customEnd);
  }

  void setCustom(DateTime start, DateTime end) {
    _range = ReportRange.custom;
    _customStart = start;
    _customEnd = end;
    state = ReportWindow.resolve(ReportRange.custom, customStart: start, customEnd: end);
  }
}

/// Selected employee filter ('all' or a user_id).
final reportEmployeeProvider = StateProvider<String>((_) => 'all');

/// The report payload for the current window. VP/Admin are org-wide; every
/// other manager is limited to their team (web useTeamAttendance parity).
final reportDataProvider = FutureProvider.autoDispose<ReportData>((ref) async {
  final w = ref.watch(reportRangeProvider);
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) {
    return const ReportData(summaries: [], daily: [], workingDays: 0);
  }
  final scope = await ref.watch(teamScopeProvider.future);
  return ref
      .read(reportsRepositoryProvider)
      .fetch(w, scopeUserIds: scope.orgWide ? null : scope.userIds);
});
