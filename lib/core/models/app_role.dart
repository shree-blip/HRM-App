/// Mirrors the Postgres `app_role` enum and the React app's role logic.
///
/// Note: the DB enum also contains the legacy value `manager`, which the
/// React `AuthContext` does not surface in its priority list. We keep it
/// here so deserialization never throws, but treat it like a generic role.
enum AppRole {
  admin,
  vp,
  supervisor,
  lineManager,
  manager,
  employee;

  /// DB string value (snake_case) <-> enum.
  String get dbValue => switch (this) {
        AppRole.lineManager => 'line_manager',
        _ => name,
      };

  static AppRole? fromDb(String? value) {
    if (value == null) return null;
    return switch (value) {
      'admin' => AppRole.admin,
      'vp' => AppRole.vp,
      'supervisor' => AppRole.supervisor,
      'line_manager' => AppRole.lineManager,
      'manager' => AppRole.manager,
      'employee' => AppRole.employee,
      _ => null,
    };
  }

  /// Priority order matching the React `fetchRole` logic: a user may hold
  /// multiple roles; the highest-priority one wins.
  static const List<AppRole> _priority = [
    AppRole.admin,
    AppRole.vp,
    AppRole.supervisor,
    AppRole.lineManager,
    AppRole.employee,
  ];

  /// Picks the highest-priority role from a list of role strings.
  static AppRole? highest(List<String> roleStrings) {
    final roles = roleStrings.map(AppRole.fromDb).whereType<AppRole>().toSet();
    if (roles.isEmpty) return null;
    for (final p in _priority) {
      if (roles.contains(p)) return p;
    }
    return roles.first;
  }
}

extension AppRoleFlags on AppRole? {
  bool get isAdmin => this == AppRole.admin;

  /// Matches React `isVP` (admin counts as VP).
  bool get isVp => this == AppRole.vp || this == AppRole.admin;

  bool get isSupervisor => this == AppRole.supervisor;

  /// Matches React `isManager`.
  bool get isManager =>
      this == AppRole.vp ||
      this == AppRole.admin ||
      this == AppRole.supervisor ||
      this == AppRole.lineManager;
}
