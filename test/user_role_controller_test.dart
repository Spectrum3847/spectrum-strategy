import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';

import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

void main() {
  group('UserRole.fromString', () {
    test('parses known role strings', () {
      expect(UserRole.fromString('viewer'), UserRole.viewer);
      expect(UserRole.fromString('scouter'), UserRole.scouter);
      expect(UserRole.fromString('strategy'), UserRole.strategy);
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('developer'), UserRole.developer);
    });

    test('falls back to viewer for unknown/null values', () {
      expect(UserRole.fromString(null), UserRole.viewer);
      expect(UserRole.fromString(''), UserRole.viewer);
      expect(UserRole.fromString('unknown'), UserRole.viewer);
    });
  });

  group('UserRole.tryParse', () {
    test('parses known role strings', () {
      expect(UserRole.tryParse('viewer'), UserRole.viewer);
      expect(UserRole.tryParse('scouter'), UserRole.scouter);
      expect(UserRole.tryParse('admin'), UserRole.admin);
      expect(UserRole.tryParse('developer'), UserRole.developer);
    });

    test('returns null for unknown/null values', () {
      expect(UserRole.tryParse(null), isNull);
      expect(UserRole.tryParse(''), isNull);
      expect(UserRole.tryParse('unknown'), isNull);
    });
  });

  group('UserRoleSetPermissions', () {
    test('viewer only: no tabs, no debug, no manage', () {
      final roles = {UserRole.viewer};
      expect(roles.visibleTabIndices, isEmpty);
      expect(roles.canManageUsers, isFalse);
      expect(roles.isDebug, isFalse);
    });

    test('scouter: Scout + Docs + Settings + Schedule', () {
      expect({UserRole.scouter}.visibleTabIndices, [1, 4, 6, 7]);
    });

    test('Schedule tab goes to every member role, never to viewer', () {
      expect({UserRole.viewer}.visibleTabIndices, isNot(contains(7)));
      for (final role in [
        UserRole.scouter,
        UserRole.strategy,
        UserRole.admin,
        UserRole.developer,
      ]) {
        expect({role}.visibleTabIndices, contains(7), reason: role.name);
      }

      for (final role in UserRole.values) {
        if (role == UserRole.viewer) continue;
        expect({role}.secondaryTabIndices, contains(7), reason: role.name);
        expect({role}.primaryTabIndices, isNot(contains(7)), reason: role.name);
      }
    });

    test('a scouter has a single primary tab and no bottom bar', () {
      const scouter = {UserRole.scouter};
      expect(scouter.primaryTabIndices, [1]);
      expect(scouter.secondaryTabIndices, [4, 6, 7]);
    });

    test('every visible tab lands in exactly one of the two groups', () {
      for (final role in UserRole.values) {
        final roles = {role};
        final primary = roles.primaryTabIndices;
        final secondary = roles.secondaryTabIndices;
        expect(
          [...primary, ...secondary]..sort(),
          roles.visibleTabIndices,
          reason: '${role.name}: a tab must not be missing or duplicated',
        );
        expect(
          primary.toSet().intersection(secondary.toSet()),
          isEmpty,
          reason: '${role.name}: a tab must not be in both groups',
        );
      }
    });

    test('isMember: true for any non-viewer role, false for viewer only', () {
      expect({UserRole.viewer}.isMember, isFalse);
      expect({UserRole.scouter}.isMember, isTrue);
      expect({UserRole.strategy}.isMember, isTrue);
      expect({UserRole.admin}.isMember, isTrue);
      expect({UserRole.developer}.isMember, isTrue);
      expect({UserRole.viewer, UserRole.scouter}.isMember, isTrue);
    });

    test('strategy: all tabs except Users (incl Docs)', () {
      expect({UserRole.strategy}.visibleTabIndices, [0, 1, 2, 3, 4, 6, 7]);
    });

    test('admin: all tabs including Docs and Users, canManageUsers', () {
      final roles = {UserRole.admin};
      expect(roles.visibleTabIndices, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(roles.canManageUsers, isTrue);
    });

    test('developer: all tabs except Users, plus Usage, isDebug', () {
      final roles = {UserRole.developer};
      expect(roles.visibleTabIndices, [0, 1, 2, 3, 4, 6, 7, 8]);
      expect(roles.isDebug, isTrue);
      expect(roles.canManageUsers, isFalse);
    });

    test('multi-role union: scouter + admin = all tabs', () {
      final roles = {UserRole.scouter, UserRole.admin};
      expect(roles.visibleTabIndices, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(roles.canManageUsers, isTrue);
    });

    test(
      'multi-role union: admin + developer = all tabs + isDebug + canManage',
      () {
        final roles = {UserRole.admin, UserRole.developer};
        expect(roles.visibleTabIndices, [0, 1, 2, 3, 4, 5, 6, 7, 8]);
        expect(roles.canManageUsers, isTrue);
        expect(roles.isDebug, isTrue);
      },
    );

    test('viewer and scouter have no config-editor capabilities', () {
      for (final roles in [
        {UserRole.viewer},
        {UserRole.scouter},
      ]) {
        expect(roles.canEditScoutConfig, isFalse);
        expect(roles.canEditAccuracyMapping, isFalse);
        expect(roles.canEditAnyEntry, isFalse);
      }
    });

    test('strategy, admin, developer have config-editor capabilities', () {
      for (final roles in [
        {UserRole.strategy},
        {UserRole.admin},
        {UserRole.developer},
      ]) {
        expect(roles.canEditScoutConfig, isTrue);
        expect(roles.canEditAccuracyMapping, isTrue);
        expect(roles.canEditAnyEntry, isTrue);
      }
    });

    test('scouter + strategy union gains editor capabilities', () {
      final roles = {UserRole.scouter, UserRole.strategy};
      expect(roles.canEditScoutConfig, isTrue);
      expect(roles.canManageUsers, isFalse);
    });
  });

  group('UserRoleController', () {
    late FakeSpectrumAuthService auth;
    late FakeUserRoleService roles;

    setUp(() {
      auth = FakeSpectrumAuthService();
      roles = FakeUserRoleService();
    });

    test('starts as viewer when signed out', () async {
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      expect(controller.roles, {UserRole.viewer});
      controller.dispose();
    });

    test('auto-assigns scouter for new user with no profile', () async {
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-new',
        displayName: 'New User',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.scouter});
      controller.dispose();
    });

    test('fetches pre-set roles after sign-in', () async {
      roles.setRoles('uid-admin', {UserRole.admin, UserRole.developer});
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-admin',
        displayName: 'Admin Dev',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.admin, UserRole.developer});
      expect(controller.canManageUsers, isTrue);
      expect(controller.isDebug, isTrue);
      controller.dispose();
    });

    test('resets to viewer after sign-out', () async {
      roles.setRole('uid-scout', UserRole.scouter);
      final initialUser = const SpectrumUser(
        uid: 'uid-scout',
        displayName: 'Scout User',
      );
      auth = FakeSpectrumAuthService(initialUser: initialUser);
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.scouter});

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.viewer});
      expect(controller.currentUid, isNull);
      controller.dispose();
    });

    test('isResolvingAuth is true until the snapshot leaves unknown', () async {
      auth.emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.unknown));
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      expect(controller.isResolvingAuth, isTrue);
      expect(controller.roles, {UserRole.viewer});

      auth.emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
      await Future<void>.delayed(Duration.zero);

      expect(controller.isResolvingAuth, isFalse);
      controller.dispose();
    });

    test('bootstrap is idempotent', () async {
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await Future.wait([controller.bootstrap(), controller.bootstrap()]);
      expect(controller.roles, {UserRole.viewer});
      controller.dispose();
    });

    test('notifies listeners when roles change', () async {
      roles.setRole('uid-strat', UserRole.strategy);
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-strat',
        displayName: 'Strat User',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.strategy});
      expect(notifyCount, greaterThan(0));
      controller.dispose();
    });

    test('updateUserRoles updates roles via service', () async {
      roles.setRole('uid-admin', UserRole.admin);
      roles.setRole('uid-target', UserRole.scouter);
      final initialUser = const SpectrumUser(
        uid: 'uid-admin',
        displayName: 'Admin',
      );
      auth = FakeSpectrumAuthService(initialUser: initialUser);
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);

      expect(controller.canManageUsers, isTrue);

      await controller.updateUserRoles('uid-target', {
        UserRole.strategy,
        UserRole.scouter,
      });

      final profiles = await roles.streamAllProfiles().first;
      final target = profiles.firstWhere((p) => p.uid == 'uid-target');
      expect(target.roles, {UserRole.strategy, UserRole.scouter});
      controller.dispose();
    });

    test(
      'updateUserRoles throws for non-admins (release-mode guard)',
      () async {
        roles.setRole('uid-scouter', UserRole.scouter);
        auth = FakeSpectrumAuthService(
          initialUser: const SpectrumUser(uid: 'uid-scouter', displayName: 'S'),
        );
        final controller = UserRoleController(
          authService: auth,
          roleService: roles,
        );
        await controller.bootstrap();
        await Future<void>.delayed(Duration.zero);

        expect(
          () => controller.updateUserRoles('uid-x', {UserRole.scouter}),
          throwsStateError,
        );
        controller.dispose();
      },
    );

    test('updateUserRoles throws for the admin\'s own uid', () async {
      roles.setRole('uid-admin', UserRole.admin);
      auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'uid-admin', displayName: 'A'),
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roles,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);

      expect(
        () => controller.updateUserRoles('uid-admin', {UserRole.viewer}),
        throwsStateError,
      );
      controller.dispose();
    });
  });

  group('a failed role fetch', () {
    test('drops to viewer and reports the reason', () async {
      final auth = FakeSpectrumAuthService();
      final roleService = FakeUserRoleService()
        ..setRoles('uid-1', {UserRole.admin})
        ..fetchFailure = StateError('firestore down');
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-1',
        displayName: 'Admin',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roleService,
      );
      await controller.bootstrap();

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.viewer});
      expect(controller.rolesError, isA<StateError>());
      controller.dispose();
    });

    test('a later success clears the error', () async {
      final auth = FakeSpectrumAuthService();
      final roleService = FakeUserRoleService()
        ..setRoles('uid-1', {UserRole.strategy})
        ..fetchFailure = StateError('offline');
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-1',
        displayName: 'Sam',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roleService,
      );
      await controller.bootstrap();

      await auth.signIn();
      await Future<void>.delayed(Duration.zero);
      expect(controller.rolesError, isNotNull);

      roleService.fetchFailure = null;
      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.roles, {UserRole.strategy});
      expect(controller.rolesError, isNull);
      controller.dispose();
    });

    test('signing out clears the error', () async {
      final auth = FakeSpectrumAuthService();
      final roleService = FakeUserRoleService()
        ..fetchFailure = StateError('offline');
      auth.nextSignInUser = const SpectrumUser(
        uid: 'uid-1',
        displayName: 'Sam',
      );
      final controller = UserRoleController(
        authService: auth,
        roleService: roleService,
      );
      await controller.bootstrap();
      await auth.signIn();
      await Future<void>.delayed(Duration.zero);
      expect(controller.rolesError, isNotNull);

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(controller.rolesError, isNull);
      expect(controller.roles, {UserRole.viewer});
      controller.dispose();
    });
  });

  group('isResolvingAuth covers the roles fetch, not just the snapshot', () {
    test(
      'stays true while a signed-in user\'s roles are still being fetched',
      () async {
        final auth = FakeSpectrumAuthService();
        final roleService = FakeUserRoleService()..gate = Completer<void>();
        auth.nextSignInUser = const SpectrumUser(
          uid: 'uid-1',
          displayName: 'Sam',
          email: 'sam@example.com',
        );
        roleService.setRole('uid-1', UserRole.strategy);
        final controller = UserRoleController(
          authService: auth,
          roleService: roleService,
        );
        await controller.bootstrap();
        await auth.signIn();
        await Future<void>.delayed(Duration.zero);

        expect(auth.snapshot.state, SpectrumAuthState.signedIn);
        expect(controller.visibleTabIndices, isEmpty);
        expect(
          controller.isResolvingAuth,
          isTrue,
          reason: 'no tabs yet, but that is the fetch, not a lack of access',
        );

        roleService.gate!.complete();
        await Future<void>.delayed(Duration.zero);

        expect(controller.isResolvingAuth, isFalse);
        expect(controller.visibleTabIndices, isNotEmpty);
        controller.dispose();
      },
    );

    test('a failed roles fetch still settles, rather than spinning', () async {
      final auth = FakeSpectrumAuthService();
      final roleService = FakeUserRoleService()
        ..fetchFailure = StateError('offline');
      final controller = UserRoleController(
        authService: auth,
        roleService: roleService,
      );
      await controller.bootstrap();
      await auth.signIn();
      await Future<void>.delayed(Duration.zero);

      expect(controller.isResolvingAuth, isFalse);
      expect(controller.rolesError, isNotNull);
      controller.dispose();
    });

    test(
      'an error snapshot overtaking an in-flight fetch still settles',
      () async {
        final auth = FakeSpectrumAuthService();
        final roleService = FakeUserRoleService()..gate = Completer<void>();
        final controller = UserRoleController(
          authService: auth,
          roleService: roleService,
        );
        await controller.bootstrap();
        await auth.signIn();
        await Future<void>.delayed(Duration.zero);
        expect(controller.isResolvingAuth, isTrue);

        auth.emit(
          const SpectrumAuthSnapshot(
            state: SpectrumAuthState.error,
            error: 'google_sign_in unavailable',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.isResolvingAuth, isFalse);
        controller.dispose();
      },
    );
  });

  group('display name and account linking', () {
    Future<UserRoleController> boot(
      FakeSpectrumAuthService auth,
      FakeUserRoleService roleService,
    ) async {
      final controller = UserRoleController(
        authService: auth,
        roleService: roleService,
      );
      await controller.bootstrap();
      await Future<void>.delayed(Duration.zero);
      return controller;
    }

    test('publishes the profile name onto the auth session', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(
          uid: 'u1',
          displayName: 'Google Name',
          email: 'u1@example.com',
        ),
      );
      final roleService = FakeUserRoleService()
        ..setProfile(
          'u1',
          displayName: 'Chosen Name',
          roles: {UserRole.scouter},
        );
      final controller = await boot(auth, roleService);

      expect(auth.displayNameUpdates, ['Chosen Name']);
      expect(controller.displayName, 'Chosen Name');
      controller.dispose();
    });

    test('a linked secondary submits under the primary name', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(
          uid: 'second',
          displayName: 'School Account',
          email: 'dana@school.edu',
        ),
      );
      final roleService = FakeUserRoleService()
        ..setProfile(
          'primary',
          displayName: 'Dana Strategist',
          email: 'dana@example.com',
          roles: {UserRole.strategy},
          linkedEmails: ['dana@school.edu'],
        )
        ..setProfile(
          'second',
          displayName: 'School Account',
          email: 'dana@school.edu',
          roles: {UserRole.strategy},
          canonicalUid: 'primary',
        );
      final controller = await boot(auth, roleService);

      expect(controller.isLinkedSecondary, isTrue);
      expect(controller.displayName, 'Dana Strategist');
      expect(auth.displayNameUpdates, ['Dana Strategist']);

      expect(controller.roles, {UserRole.strategy});
      controller.dispose();
    });

    test('an admin renames a member', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin})
        ..setProfile('u1', displayName: 'Old', roles: {UserRole.scouter});
      final controller = await boot(auth, roleService);

      await controller.updateDisplayName('u1', '  New Name  ');

      expect((await roleService.fetchProfile('u1'))!.displayName, 'New Name');
      controller.dispose();
    });

    test('a member cannot rename anyone', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'u1', displayName: 'Scout'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('u1', displayName: 'Scout', roles: {UserRole.scouter})
        ..setProfile('u2', displayName: 'Other', roles: {UserRole.scouter});
      final controller = await boot(auth, roleService);

      expect(
        () => controller.updateDisplayName('u2', 'Hijack'),
        throwsA(isA<StateError>()),
      );
      controller.dispose();
    });

    test('an admin cannot rename themselves via the GUI', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin});
      final controller = await boot(auth, roleService);

      expect(
        () => controller.updateDisplayName('admin', 'Renamed'),
        throwsA(isA<StateError>()),
      );
      controller.dispose();
    });

    test('renaming rejects an empty name', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin})
        ..setProfile('u1', displayName: 'Old', roles: {UserRole.scouter});
      final controller = await boot(auth, roleService);

      expect(
        () => controller.updateDisplayName('u1', '   '),
        throwsA(isA<ArgumentError>()),
      );
      controller.dispose();
    });

    test('an admin links a second account and copies its roles', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin})
        ..setProfile(
          'primary',
          displayName: 'Dana',
          email: 'dana@example.com',
          roles: {UserRole.strategy},
        )
        ..setProfile(
          'second',
          displayName: 'Dana School',
          email: 'dana@school.edu',
          roles: {UserRole.viewer},
        );
      final controller = await boot(auth, roleService);

      await controller.linkAccounts(
        secondary: (await roleService.fetchProfile('second'))!,
        primary: (await roleService.fetchProfile('primary'))!,
      );

      final second = (await roleService.fetchProfile('second'))!;
      expect(second.canonicalUid, 'primary');
      expect(second.roles, {UserRole.strategy});
      expect((await roleService.fetchProfile('primary'))!.linkedEmails, [
        'dana@school.edu',
      ]);
      controller.dispose();
    });

    test('a non-admin cannot link accounts', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'u1', displayName: 'Scout'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('u1', displayName: 'Scout', roles: {UserRole.scouter})
        ..setProfile('other', displayName: 'Other', email: 'o@example.com');
      final controller = await boot(auth, roleService);

      expect(
        () async => controller.linkAccounts(
          secondary: (await roleService.fetchProfile('other'))!,
          primary: (await roleService.fetchProfile('u1'))!,
        ),
        throwsA(isA<StateError>()),
      );
      controller.dispose();
    });

    test('a role change skips the admin\'s own linked account', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile(
          'admin',
          displayName: 'Admin',
          roles: {UserRole.admin},
          canonicalUid: 'primary',
        )
        ..setProfile('primary', displayName: 'Dana', roles: {UserRole.scouter})
        ..setProfile(
          'second',
          displayName: 'Dana School',
          roles: {UserRole.scouter},
          canonicalUid: 'primary',
        );
      final controller = await boot(auth, roleService);
      final roster = [
        (await roleService.fetchProfile('primary'))!,
        (await roleService.fetchProfile('admin'))!,
        (await roleService.fetchProfile('second'))!,
      ];

      await controller.updateUserRolesWithLinked(roster.first, {
        UserRole.strategy,
      }, roster);

      expect((await roleService.fetchProfile('admin'))!.roles, {
        UserRole.admin,
      });

      expect((await roleService.fetchProfile('second'))!.roles, {
        UserRole.strategy,
      });
      controller.dispose();
    });

    test('a role change on a secondary reaches the whole person', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin})
        ..setProfile('primary', displayName: 'Dana', roles: {UserRole.scouter})
        ..setProfile(
          'second',
          displayName: 'Dana School',
          roles: {UserRole.scouter},
          canonicalUid: 'primary',
        )
        ..setProfile(
          'third',
          displayName: 'Dana Spare',
          roles: {UserRole.scouter},
          canonicalUid: 'primary',
        );
      final controller = await boot(auth, roleService);
      final roster = [
        (await roleService.fetchProfile('primary'))!,
        (await roleService.fetchProfile('second'))!,
        (await roleService.fetchProfile('third'))!,
      ];

      await controller.updateUserRolesWithLinked(roster[1], {
        UserRole.strategy,
      }, roster);

      for (final uid in ['primary', 'second', 'third']) {
        expect((await roleService.fetchProfile(uid))!.roles, {
          UserRole.strategy,
        }, reason: '$uid should carry the new roles');
      }
      controller.dispose();
    });

    test('one failed write does not strand the other accounts', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin})
        ..setProfile('primary', displayName: 'Dana', roles: {UserRole.scouter})
        ..setProfile(
          'second',
          displayName: 'Dana School',
          roles: {UserRole.scouter},
          canonicalUid: 'primary',
        )
        ..setProfile(
          'third',
          displayName: 'Dana Spare',
          roles: {UserRole.scouter},
          canonicalUid: 'primary',
        );
      roleService.failingRoleWrites.add('second');
      final controller = await boot(auth, roleService);
      final roster = [
        (await roleService.fetchProfile('primary'))!,
        (await roleService.fetchProfile('second'))!,
        (await roleService.fetchProfile('third'))!,
      ];

      await expectLater(
        controller.updateUserRolesWithLinked(roster.first, {
          UserRole.strategy,
        }, roster),
        throwsStateError,
      );

      expect((await roleService.fetchProfile('primary'))!.roles, {
        UserRole.strategy,
      });
      expect((await roleService.fetchProfile('third'))!.roles, {
        UserRole.strategy,
      });
      expect((await roleService.fetchProfile('second'))!.roles, {
        UserRole.scouter,
      });
      controller.dispose();
    });

    test('a role change reaches every linked account', () async {
      final auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin', displayName: 'Admin'),
      );
      final roleService = FakeUserRoleService()
        ..setProfile('admin', displayName: 'Admin', roles: {UserRole.admin})
        ..setProfile('primary', displayName: 'Dana', roles: {UserRole.scouter})
        ..setProfile(
          'second',
          displayName: 'Dana School',
          roles: {UserRole.scouter},
          canonicalUid: 'primary',
        );
      final controller = await boot(auth, roleService);
      final roster = [
        (await roleService.fetchProfile('primary'))!,
        (await roleService.fetchProfile('second'))!,
      ];

      await controller.updateUserRolesWithLinked(roster.first, {
        UserRole.strategy,
      }, roster);

      expect((await roleService.fetchProfile('second'))!.roles, {
        UserRole.strategy,
      });
      controller.dispose();
    });
  });
}
