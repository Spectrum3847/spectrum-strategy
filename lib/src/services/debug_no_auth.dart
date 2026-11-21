import 'package:flutter/foundation.dart';

import '../models/user_role.dart';

const bool debugNoAuth =
    !kReleaseMode && bool.fromEnvironment('SPECTRUM_DEBUG_NO_AUTH');

const String _debugRolesDefine = String.fromEnvironment('SPECTRUM_DEBUG_ROLES');

Set<UserRole> get localSessionRoles =>
    debugNoAuth ? parseDebugRoles(_debugRolesDefine) : defaultLocalRoles;

const Set<UserRole> defaultLocalRoles = {UserRole.strategy};

Set<UserRole> parseDebugRoles(String value) {
  final roles = {
    for (final name in value.split(','))
      ?UserRole.tryParse(name.trim().toLowerCase()),
  };
  return roles.isEmpty ? defaultLocalRoles : roles;
}
