import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import 'onboarding_models.dart';
import 'onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((_) => OnboardingRepository());

class OnboardingState {
  const OnboardingState({this.onboarding = const [], this.offboarding = const [], this.loading = true});
  final List<OnboardingWorkflow> onboarding;
  final List<OffboardingWorkflow> offboarding;
  final bool loading;

  List<OnboardingWorkflow> get active => onboarding.where((w) => w.status != 'completed').toList();
  List<OnboardingWorkflow> get completed => onboarding.where((w) => w.status == 'completed').toList();
  List<OffboardingWorkflow> get activeOffboarding => offboarding.where((w) => w.status != 'completed').toList();

  OnboardingState copyWith({List<OnboardingWorkflow>? onboarding, List<OffboardingWorkflow>? offboarding, bool? loading}) =>
      OnboardingState(
        onboarding: onboarding ?? this.onboarding,
        offboarding: offboarding ?? this.offboarding,
        loading: loading ?? this.loading,
      );
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(OnboardingController.new);

class OnboardingController extends Notifier<OnboardingState> {
  RealtimeChannel? _channel;
  OnboardingRepository get _repo => ref.read(onboardingRepositoryProvider);

  @override
  OnboardingState build() {
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_teardown);
    if (uid == null) return const OnboardingState(loading: false);
    Future.microtask(_load);
    return const OnboardingState(loading: true);
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_repo.fetchOnboarding(), _repo.fetchOffboarding()]);
      state = OnboardingState(
        onboarding: results[0] as List<OnboardingWorkflow>,
        offboarding: results[1] as List<OffboardingWorkflow>,
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
    _subscribe();
  }

  void _subscribe() {
    if (_channel != null) return;
    _channel = supabase.channel('onboarding-changes')
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'onboarding_workflows', callback: (_) => refresh())
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'onboarding_tasks', callback: (_) => refresh())
      ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'offboarding_workflows', callback: (_) => refresh())
      ..subscribe();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([_repo.fetchOnboarding(), _repo.fetchOffboarding()]);
      state = state.copyWith(
        onboarding: results[0] as List<OnboardingWorkflow>,
        offboarding: results[1] as List<OffboardingWorkflow>,
        loading: false,
      );
    } catch (_) {}
  }

  Future<void> toggleTask(String taskId, bool completed) async {
    await _repo.toggleTask(taskId, completed);
    await refresh();
  }

  Future<void> createNewHire(NewHireData d) async {
    await _repo.createNewHireWithOnboarding(d);
    await refresh();
  }

  Future<void> createOffboarding(String employeeId, String lastWorkingDate, String? reason) async {
    await _repo.createOffboarding(employeeId, lastWorkingDate, reason);
    await refresh();
  }

  Future<void> updateOffboarding(String workflowId, String key) async {
    await _repo.updateOffboarding(workflowId, key);
    await refresh();
  }

  Future<void> deleteOnboarding(String workflowId) async {
    await _repo.deleteOnboarding(workflowId);
    await refresh();
  }

  Future<void> deleteOffboarding(String workflowId) async {
    await _repo.deleteOffboarding(workflowId);
    await refresh();
  }

  void _teardown() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }
}

final myOnboardingProvider = FutureProvider.autoDispose<OnboardingWorkflow?>(
  (ref) => ref.read(onboardingRepositoryProvider).myOnboarding(),
);

final myOffboardingProvider = FutureProvider.autoDispose<OffboardingWorkflow?>(
  (ref) => ref.read(onboardingRepositoryProvider).myOffboarding(),
);
