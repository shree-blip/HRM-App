import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import 'document_models.dart';
import 'documents_repository.dart';

final documentsRepositoryProvider =
    Provider<DocumentsRepository>((_) => DocumentsRepository());

/// Documents visible to the current user (client-side category rules), with
/// the same explicit-override logic as the web hook.
final documentsProvider = FutureProvider.autoDispose<List<HrDocument>>((ref) {
  final auth = ref.watch(authControllerProvider);
  final perms = ref.watch(permissionsControllerProvider);
  if (auth.user == null) return Future.value(const []);
  return ref.read(documentsRepositoryProvider).visibleDocuments(
        isAdmin: auth.isAdmin,
        isVp: auth.isVp,
        isManager: auth.isManager,
        isLineManager: auth.isLineManager,
        hasManageDocuments: perms.has(Permission.manageDocuments),
        manageDocsOverridden: perms.hasExplicitOverride(Permission.manageDocuments),
      );
});

/// Active employees for the assign pickers.
final documentsEmployeesProvider =
    FutureProvider.autoDispose<List<DocEmployee>>(
  (ref) => ref.read(documentsRepositoryProvider).employees(),
);

/// Categories the user may add (web getAvailableCategories): VP gets Contracts;
/// everyone gets Policies / Compliance / Leave Evidence.
List<String> allowedAddCategories(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return [
    if (auth.isVp) 'Contracts',
    'Policies',
    'Compliance',
    'Leave Evidence',
  ];
}

/// Whether the user is "manager or above" (drives Compliance multi-employee UI).
bool isManagerOrAbove(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth.isAdmin || auth.isVp || auth.isManager || auth.isLineManager;
}
