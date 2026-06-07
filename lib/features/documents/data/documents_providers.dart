import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'document_models.dart';
import 'documents_repository.dart';

final documentsRepositoryProvider =
    Provider<DocumentsRepository>((_) => DocumentsRepository());

/// Documents visible to the current user (client-side category rules).
final documentsProvider = FutureProvider.autoDispose<List<HrDocument>>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth.user == null) return Future.value(const []);
  return ref.read(documentsRepositoryProvider).visibleDocuments(
        isAdmin: auth.isAdmin,
        isVp: auth.isVp,
        isManager: auth.isManager,
        isLineManager: auth.isLineManager,
      );
});

/// Employees for the assign picker.
final documentsEmployeesProvider =
    FutureProvider.autoDispose<List<({String id, String name})>>(
  (ref) => ref.read(documentsRepositoryProvider).employees(),
);
