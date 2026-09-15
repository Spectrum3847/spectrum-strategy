import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/local_only_services.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';

void main() {
  test('LocalOnlyAuthService presents a signed-in local session', () {
    final auth = LocalOnlyAuthService();
    addTearDown(auth.dispose);
    expect(auth.snapshot.state, SpectrumAuthState.signedIn);
    expect(auth.currentUser?.uid, 'local');
  });

  test('LocalUserRoleService grants the strategy role (no admin)', () async {
    final profile = await LocalUserRoleService().fetchOrCreateProfile(
      uid: 'local',
    );
    final roles = profile.roles;
    expect(roles, {UserRole.strategy});
    expect(roles.canManageUsers, isFalse);
    expect(await LocalUserRoleService().streamAllProfiles().toList(), isEmpty);
  });

  test(
    'local auth + role wiring yields a usable (non-viewer) session offline',
    () async {
      final auth = LocalOnlyAuthService();
      final controller = UserRoleController(
        authService: auth,
        roleService: LocalUserRoleService(),
      );
      addTearDown(() async {
        controller.dispose();
        await auth.dispose();
      });

      await controller.bootstrap();

      expect(controller.roles, {UserRole.strategy});
      expect(controller.visibleTabIndices, isNotEmpty);
      expect(controller.canManageUsers, isFalse);
    },
  );
}
