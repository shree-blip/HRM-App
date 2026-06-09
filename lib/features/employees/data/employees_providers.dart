import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions/permission.dart';
import '../../../core/permissions/permissions_controller.dart';
import 'employee.dart';
import 'employees_repository.dart';

final employeesRepositoryProvider =
    Provider<EmployeesRepository>((_) => EmployeesRepository());

/// Active employees for the line-manager picker (create form).
final employeeManagersProvider =
    FutureProvider.autoDispose<List<ManagerOption>>(
  (ref) => ref.read(employeesRepositoryProvider).managers(),
);

/// Can the current user add/edit/deactivate employees (web gates on isManager;
/// admins/VP and an explicit manage_employees override also qualify).
bool canManageEmployees(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth.isManager ||
      auth.isAdmin ||
      auth.isVp ||
      ref.read(permissionsControllerProvider).has(Permission.manageEmployees);
}

/// All employees visible to the current user (RLS-scoped).
final employeesListProvider =
    FutureProvider.autoDispose<List<EmployeeDirectoryItem>>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  return ref.read(employeesRepositoryProvider).list();
});

/// A single employee by id (for deep links / refresh where the list item
/// wasn't passed through navigation).
final employeeByIdProvider =
    FutureProvider.autoDispose.family<EmployeeDirectoryItem?, String>(
  (ref, id) => ref.read(employeesRepositoryProvider).byId(id),
);

/// Managers + team for an employee.
final employeeRelationsProvider =
    FutureProvider.autoDispose.family<EmployeeRelations, String>(
  (ref, id) => ref.read(employeesRepositoryProvider).relations(id),
);
