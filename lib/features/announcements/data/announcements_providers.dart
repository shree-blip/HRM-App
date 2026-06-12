import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../../core/supabase/supabase_client.dart';
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

/// Realtime refresh on announcements changes (web shared
/// "announcements-realtime-shared" channel). Watched by AnnouncementsScreen.
final announcementsRealtimeProvider = Provider.autoDispose<void>((ref) {
  final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (uid == null) return;
  final channel = supabase.channel('announcements-realtime-$uid')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'announcements',
      callback: (_) {
        ref.invalidate(activeAnnouncementsProvider);
        ref.invalidate(announcementHistoryProvider);
      },
    )
    ..subscribe();
  ref.onDispose(() => supabase.removeChannel(channel));
});

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
