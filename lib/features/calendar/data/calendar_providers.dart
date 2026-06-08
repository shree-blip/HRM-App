import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((_) => CalendarRepository());

/// All entries (hardcoded + custom DB), sorted by date.
final calendarEntriesProvider = FutureProvider.autoDispose<List<CalendarEntry>>(
  (ref) => ref.read(calendarRepositoryProvider).allEntries(),
);

/// Managers or holders of manage_calendar can add/delete events.
bool canManageCalendar(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth.isManager ||
      auth.isVp ||
      auth.isAdmin ||
      ref.read(permissionsControllerProvider).has(Permission.manageCalendar);
}
