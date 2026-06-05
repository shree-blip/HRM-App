import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import 'employee.dart';
import 'employees_repository.dart';

final employeesRepositoryProvider =
    Provider<EmployeesRepository>((_) => EmployeesRepository());

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
