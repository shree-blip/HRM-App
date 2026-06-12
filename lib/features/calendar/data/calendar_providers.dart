import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import '../../../core/supabase/supabase_client.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((_) => CalendarRepository());

/// All entries (hardcoded + custom DB), sorted by date.
final calendarEntriesProvider = FutureProvider.autoDispose<List<CalendarEntry>>(
  (ref) => ref.read(calendarRepositoryProvider).allEntries(),
);

/// A birthday/anniversary milestone source row (web useMilestones reads the
/// profiles table: date_of_birth + joining_date of non-inactive people).
class MilestoneProfile {
  const MilestoneProfile({required this.name, this.dob, this.joining});
  final String name;
  final DateTime? dob;
  final DateTime? joining;
}

final milestoneProfilesProvider =
    FutureProvider.autoDispose<List<MilestoneProfile>>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  final rows = await supabase
      .from('profiles')
      .select('first_name, last_name, date_of_birth, joining_date, status')
      .neq('status', 'inactive');
  return [
    for (final r in rows as List)
      MilestoneProfile(
        name: '${(r as Map)['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim(),
        dob: r['date_of_birth'] != null
            ? DateTime.tryParse(r['date_of_birth'] as String)
            : null,
        joining: r['joining_date'] != null
            ? DateTime.tryParse(r['joining_date'] as String)
            : null,
      ),
  ].where((p) => p.name.isNotEmpty).toList();
});

/// Managers or holders of manage_calendar can add/delete events.
bool canManageCalendar(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth.isManager ||
      auth.isVp ||
      auth.isAdmin ||
      ref.read(permissionsControllerProvider).has(Permission.manageCalendar);
}
