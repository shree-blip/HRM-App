import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import 'attendance_models.dart';
import 'attendance_repository.dart';

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

/// Manager/admin team attendance (this month).
final teamAttendanceProvider =
    FutureProvider.autoDispose<List<TeamMemberAttendance>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isManager) return const [];
  return ref.read(attendanceRepositoryProvider).teamAttendance();
});

/// Live "today" team counts for the dashboard real-time card.
final liveAttendanceSummaryProvider =
    FutureProvider.autoDispose<LiveAttendanceSummary>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null || !auth.isManager) return const LiveAttendanceSummary();
  return ref.read(attendanceRepositoryProvider).liveSummary();
});
