import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((_) => SettingsRepository());

final userPreferencesProvider = FutureProvider.autoDispose<UserPreferences>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const UserPreferences());
  return ref.read(settingsRepositoryProvider).loadPreferences();
});

/// Device-local "Global Activity Alerts" toggle (web uses cross-tab/OS; on
/// mobile this is a session toggle, default on).
final activityAlertsProvider = StateProvider<bool>((_) => true);
