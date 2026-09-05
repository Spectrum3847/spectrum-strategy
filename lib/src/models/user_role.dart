enum UserRole {
  viewer,

  scouter,

  strategy,

  admin,

  developer;

  static final Map<String, UserRole> _byName = {
    for (final role in UserRole.values) role.name: role,
  };

  static UserRole fromString(String? value) =>
      tryParse(value) ?? UserRole.viewer;

  static UserRole? tryParse(String? value) =>
      value == null ? null : _byName[value];

  String get displayName {
    switch (this) {
      case UserRole.viewer:
        return 'Viewer';
      case UserRole.scouter:
        return 'Scouter';
      case UserRole.strategy:
        return 'Strategist';
      case UserRole.admin:
        return 'Admin';
      case UserRole.developer:
        return 'Developer';
    }
  }

  bool get isDebug => this == UserRole.developer;

  bool get canManageUsers => this == UserRole.admin;
}

extension UserRoleSetPermissions on Set<UserRole> {
  List<int> get visibleTabIndices {
    final tabs = <int>{};
    for (final role in this) {
      switch (role) {
        case UserRole.viewer:
          break;
        case UserRole.scouter:
          tabs.addAll(const [1, 4, 6, 7]);
        case UserRole.strategy:
          tabs.addAll(const [0, 1, 2, 3, 4, 6, 7]);

        case UserRole.developer:
          tabs.addAll(const [0, 1, 2, 3, 4, 6, 7, 8]);
        case UserRole.admin:
          tabs.addAll(const [0, 1, 2, 3, 4, 5, 6, 7]);
      }
    }
    return tabs.toList()..sort();
  }

  List<int> get primaryTabIndices =>
      visibleTabIndices.where((i) => i <= 3).toList();

  List<int> get secondaryTabIndices {
    final primary = primaryTabIndices.toSet();
    return visibleTabIndices.where((i) => !primary.contains(i)).toList();
  }

  bool get isMember => any((r) => r != UserRole.viewer);

  bool get canManageUsers => any((r) => r.canManageUsers);

  bool get isDebug => any((r) => r.isDebug);

  bool get canEditScoutConfig => any(
    (r) =>
        r == UserRole.strategy ||
        r == UserRole.admin ||
        r == UserRole.developer,
  );

  bool get canEditAccuracyMapping => any(
    (r) =>
        r == UserRole.strategy ||
        r == UserRole.admin ||
        r == UserRole.developer,
  );

  bool get canEditTraitTable => any(
    (r) =>
        r == UserRole.strategy ||
        r == UserRole.admin ||
        r == UserRole.developer,
  );

  bool get canPublishSummaries => any(
    (r) =>
        r == UserRole.strategy ||
        r == UserRole.admin ||
        r == UserRole.developer,
  );

  bool get canEditTRexAssignments => any(
    (r) =>
        r == UserRole.strategy ||
        r == UserRole.admin ||
        r == UserRole.developer,
  );

  bool get canEditAnyEntry => any(
    (r) =>
        r == UserRole.strategy ||
        r == UserRole.admin ||
        r == UserRole.developer,
  );

  String get displayText {
    final names = map((r) => r.displayName).toList()..sort();
    return names.join(', ');
  }
}
