import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'hiring_models.dart';
import 'hiring_repository.dart';

final hiringRepositoryProvider = Provider<HiringRepository>((_) => HiringRepository());

final hiringPostsProvider = FutureProvider.autoDispose<List<HiringPost>>(
  (ref) => ref.read(hiringRepositoryProvider).list(),
);

/// Only Admin/VP (Executive) can create or delete hiring posts (web canManage).
bool canManageHiring(WidgetRef ref) => ref.read(authControllerProvider).isVp;
