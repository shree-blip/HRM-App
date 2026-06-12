import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/team/team_scope.dart';
import 'leave_models.dart';
import 'leave_repository.dart';

/// Debounced realtime on leave_requests (web useLeaveRequests "leave-changes"
/// channel, 500ms debounce). Watched by the Leave + Approvals views; refreshes
/// both my-leave and team lists on any change.
final leaveRealtimeProvider = Provider.autoDispose<void>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return;
  Timer? debounce;
  final channel = supabase.channel('leave-changes-$uid')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'leave_requests',
      callback: (_) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 500), () {
          ref.invalidate(myLeaveRequestsProvider);
          ref.invalidate(teamLeaveRequestsProvider);
          ref.invalidate(leaveBalancesProvider);
        });
      },
    )
    ..subscribe();
  ref.onDispose(() {
    debounce?.cancel();
    supabase.removeChannel(channel);
  });
});

final leaveRepositoryProvider = Provider<LeaveRepository>((_) => LeaveRepository());

final myLeaveRequestsProvider =
    FutureProvider.autoDispose<List<LeaveRequest>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.read(leaveRepositoryProvider).myRequests();
});

final leaveBalancesProvider =
    FutureProvider.autoDispose<List<LeaveBalance>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.read(leaveRepositoryProvider).balances();
});

/// Remaining days in the shared Annual Leave bucket (for the paid-leave option).
final annualRemainingProvider = FutureProvider.autoDispose<num>((ref) async {
  final balances = await ref.watch(leaveBalancesProvider.future);
  for (final b in balances) {
    if (b.leaveType == 'Annual Leave') return b.remaining;
  }
  return 0;
});

/// Employees an admin/VP can assign leave to (AdminLeaveDialog employee list).
final assignableEmployeesProvider =
    FutureProvider.autoDispose<List<({String userId, String name})>>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.read(leaveRepositoryProvider).assignableEmployees();
});

/// Requests awaiting/handled for the approval view. VP/Admin org-wide; every
/// other manager limited to their team (web useLeaveRequests parity).
final teamLeaveRequestsProvider =
    FutureProvider.autoDispose<List<LeaveRequest>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null) return const [];
  final scope = await ref.watch(teamScopeProvider.future);
  return ref.read(leaveRepositoryProvider).teamRequests(
        scopeUserIds: scope.orgWide ? null : scope.userIds,
      );
});
