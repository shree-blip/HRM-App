import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import 'comment_models.dart';
import 'support_models.dart';
import 'support_repository.dart';

final supportRepositoryProvider = Provider<SupportRepository>((_) => SupportRepository());

final bugsProvider = FutureProvider.autoDispose<List<BugReport>>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(supportRepositoryProvider).bugs();
});

final grievancesProvider = FutureProvider.autoDispose<List<Grievance>>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return Future.value(const []);
  return ref.read(supportRepositoryProvider).grievances();
});

final bugCommentsProvider =
    FutureProvider.autoDispose.family<List<CommentItem>, String>(
  (ref, id) => ref.read(supportRepositoryProvider).bugComments(id),
);

/// Attachments for a grievance (file rows; signed URLs resolved on tap).
final grievanceAttachmentsProvider =
    FutureProvider.autoDispose.family<List<GrievanceAttachment>, String>(
  (ref, id) => ref.read(supportRepositoryProvider).grievanceAttachments(id),
);

/// Whether the current user is a grievance "manager" (sees internal comments,
/// can update status).
bool grievanceIsManager(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth.isAdmin ||
      auth.isVp ||
      auth.isManager ||
      ref.read(permissionsControllerProvider).has(Permission.viewGrievances) ||
      ref.read(permissionsControllerProvider).has(Permission.manageSupport);
}

final grievanceCommentsProvider =
    FutureProvider.autoDispose.family<List<CommentItem>, String>((ref, id) {
  final auth = ref.read(authControllerProvider);
  final isManager = auth.isAdmin ||
      auth.isVp ||
      auth.isManager ||
      ref.read(permissionsControllerProvider).has(Permission.viewGrievances) ||
      ref.read(permissionsControllerProvider).has(Permission.manageSupport);
  return ref.read(supportRepositoryProvider).grievanceComments(id, isManager: isManager);
});
