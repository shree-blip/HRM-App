import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import 'timezone_models.dart';
import 'timezone_repository.dart';

final timezoneRepositoryProvider = Provider<TimezoneRepository>((_) => TimezoneRepository());

final timezoneEmployeesProvider = FutureProvider.autoDispose<List<EmployeeTimezoneRow>>(
  (ref) => ref.read(timezoneRepositoryProvider).fetchEmployees(),
);

/// Gated by manage_access — same as the web route (Admin/VP).
bool canManageTimezones(WidgetRef ref) =>
    ref.read(permissionsControllerProvider).has(Permission.manageAccess);
