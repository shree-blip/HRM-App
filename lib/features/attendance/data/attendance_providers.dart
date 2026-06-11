import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/team/team_scope.dart';
import 'adjustment_models.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';
import 'live_attendance.dart';

final attendanceRepositoryProvider =
    Provider<AttendanceRepository>((_) => AttendanceRepository());

/// State held by [TimeTrackerController]: the current open log + flags.
class TimeTrackerState {
  const TimeTrackerState({this.openLog, this.loading = true, this.busy = false});
  final AttendanceLog? openLog;
  final bool loading;
  final bool busy;

  ClockStatus get status => openLog?.clockStatus ?? ClockStatus.out;

  TimeTrackerState copyWith({
    AttendanceLog? openLog,
    bool clearLog = false,
    bool? loading,
    bool? busy,
  }) =>
      TimeTrackerState(
        openLog: clearLog ? null : (openLog ?? this.openLog),
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
      );
}

/// App-wide clock state, shared by the dashboard Time Clock card and the
/// Attendance screen. Server is the source of truth; we reconcile with the
/// edge-function response and a realtime subscription on the user's logs.
final timeTrackerProvider =
    NotifierProvider<TimeTrackerController, TimeTrackerState>(
  TimeTrackerController.new,
);

class TimeTrackerController extends Notifier<TimeTrackerState> {
  AttendanceRepository get _repo => ref.read(attendanceRepositoryProvider);
  RealtimeChannel? _channel;
  String? _userId;

  @override
  TimeTrackerState build() {
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_teardown);
    if (uid == null) {
      _teardown();
      return const TimeTrackerState(loading: false);
    }
    _userId = uid;
    Future.microtask(() => _init(uid));
    return const TimeTrackerState(loading: true);
  }

  Future<void> _init(String uid) async {
    try {
      final log = await _repo.openLog(uid);
      state = TimeTrackerState(openLog: log, loading: false);
    } catch (_) {
      state = const TimeTrackerState(loading: false);
    }
    _subscribe(uid);
  }

  void _subscribe(String uid) {
    if (_channel != null) return;
    _channel = supabase
        .channel('attendance-sync-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _reloadIfIdle(),
        )
        .subscribe();
  }

  Future<void> _reloadIfIdle() async {
    if (state.busy || _userId == null) return;
    try {
      final log = await _repo.openLog(_userId!);
      state = TimeTrackerState(openLog: log, loading: false);
    } catch (_) {}
  }

  void _teardown() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<void> _run(Future<AttendanceLog?> Function() action) async {
    state = state.copyWith(busy: true);
    try {
      final log = await action();
      // clock_out / completed → no open log.
      if (log == null || log.clockOut != null) {
        state = const TimeTrackerState(openLog: null, loading: false, busy: false);
      } else {
        state = TimeTrackerState(openLog: log, loading: false, busy: false);
      }
      // Refresh stats/history after any change.
      ref.invalidate(attendanceStatsProvider);
      ref.invalidate(attendanceHistoryProvider);
    } catch (e) {
      state = state.copyWith(busy: false);
      rethrow;
    }
  }

  Future<void> clockIn({
    required String clockType,
    required String workMode,
    String? locationName,
  }) =>
      _run(() => _repo.clock(
            'clock_in',
            clockType: clockType,
            workMode: workMode,
            locationName: locationName ?? (workMode == 'wfh' ? 'Home' : 'Office'),
          ),);

  Future<void> clockOut() =>
      _run(() => _repo.clock('clock_out', logId: state.openLog!.id));

  Future<void> startBreak() =>
      _run(() => _repo.clock('start_break', logId: state.openLog!.id));

  Future<void> endBreak() =>
      _run(() => _repo.clock('end_break', logId: state.openLog!.id));

  Future<void> startPause() =>
      _run(() => _repo.clock('start_pause', logId: state.openLog!.id));

  Future<void> endPause({String? newWorkMode}) => _run(() => _repo.clock(
        'end_pause',
        logId: state.openLog!.id,
        newWorkMode: newWorkMode,
      ),);
}

/// Today / week / month net hours for the current user.
final attendanceStatsProvider =
    FutureProvider.autoDispose<AttendanceStats>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const AttendanceStats();
  final repo = ref.read(attendanceRepositoryProvider);
  return repo.statsFrom(await repo.monthLogs(uid));
});

/// This month's logs (newest first) for the My History list.
final attendanceHistoryProvider =
    FutureProvider.autoDispose<List<AttendanceLog>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.read(attendanceRepositoryProvider).monthLogs(uid);
});

/// Manager/admin team attendance (this month). VP/Admin org-wide; every other
/// manager limited to their team (web useTeamAttendance parity).
final teamAttendanceProvider =
    FutureProvider.autoDispose<List<TeamMemberAttendance>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isManager) return const [];
  final scope = await ref.watch(teamScopeProvider.future);
  return ref.read(attendanceRepositoryProvider).teamAttendance(
        scopeUserIds: scope.orgWide ? null : scope.userIds,
      );
});

final liveAttendanceRepositoryProvider =
    Provider<LiveAttendanceRepository>((_) => LiveAttendanceRepository());

/// Full Live Attendance snapshot (employees + summary + events), auto-refreshed
/// by realtime changes on attendance_logs / attendance_break_sessions and a
/// 60s poll — mirrors the web RealTimeAttendanceWidget.
final liveAttendanceProvider =
    AsyncNotifierProvider<LiveAttendanceController, LiveData>(
  LiveAttendanceController.new,
);

/// The current user's attendance adjustment requests (newest first).
final myAdjustmentsProvider =
    FutureProvider.autoDispose<List<AdjustmentRequest>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.read(attendanceRepositoryProvider).myAdjustmentRequests();
});

/// Team attendance adjustment requests for the approvals view. RLS scopes
/// which requests are visible (managers/admins see their team's), so we don't
/// pre-gate on the client role flags.
final teamAdjustmentsProvider =
    FutureProvider.autoDispose<List<AdjustmentRequest>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.read(attendanceRepositoryProvider).teamAdjustments();
});

/// Month-range activity events for the full-activity timeline (Week/Month).
final fullActivityProvider =
    FutureProvider.autoDispose<List<LiveEvent>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  final now = DateTime.now().toUtc();
  final monthStart = DateTime.utc(now.year, now.month, 1);
  return ref.read(liveAttendanceRepositoryProvider).eventsSince(monthStart);
});

class LiveAttendanceController extends AsyncNotifier<LiveData> {
  Timer? _timer;
  RealtimeChannel? _channel;

  @override
  Future<LiveData> build() async {
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_dispose);
    if (uid == null) return LiveData.empty;
    _setup();
    return ref.read(liveAttendanceRepositoryProvider).liveData();
  }

  void _setup() {
    _channel ??= supabase
        .channel('live-attendance')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_logs',
          callback: (_) => _refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_break_sessions',
          callback: (_) => _refresh(),
        )
        .subscribe();
    _timer ??= Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final data = await ref.read(liveAttendanceRepositoryProvider).liveData();
      state = AsyncData(data);
    } catch (_) {
      // keep last good snapshot
    }
  }

  Future<void> refresh() => _refresh();

  void _dispose() {
    _timer?.cancel();
    _timer = null;
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }
}
