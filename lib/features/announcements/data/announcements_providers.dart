import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import 'announcement_models.dart';
import 'announcements_repository.dart';

final announcementsRepositoryProvider =
    Provider<AnnouncementsRepository>((_) => AnnouncementsRepository());

final activeAnnouncementsProvider = FutureProvider.autoDispose<List<Announcement>>(
  (ref) => ref.read(announcementsRepositoryProvider).active(),
);

final announcementHistoryProvider = FutureProvider.autoDispose<List<Announcement>>(
  (ref) => ref.read(announcementsRepositoryProvider).history(),
);

/// Can the current user add/remove announcements (perms or admin/vp/supervisor).
bool canManageAnnouncements(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  final perms = ref.read(permissionsControllerProvider);
  return auth.isAdmin ||
      auth.isVp ||
      auth.isSupervisor ||
      perms.has(Permission.addAnnouncement) ||
      perms.has(Permission.editAnnouncement) ||
      perms.has(Permission.deleteAnnouncement);
}
