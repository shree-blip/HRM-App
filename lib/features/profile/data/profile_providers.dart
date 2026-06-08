import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((_) => ProfileRepository());

final profileProvider = FutureProvider.autoDispose<ProfileData?>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(null);
  return ref.read(profileRepositoryProvider).load();
});
