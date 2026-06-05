import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'asset_models.dart';
import 'asset_repository.dart';

final assetRepositoryProvider = Provider<AssetRepository>((_) => AssetRepository());

/// Asset requests visible to the current user (RLS-scoped).
final assetRequestsProvider =
    FutureProvider.autoDispose<List<AssetRequest>>((ref) async {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return const [];
  return ref.read(assetRepositoryProvider).visibleRequests();
});
