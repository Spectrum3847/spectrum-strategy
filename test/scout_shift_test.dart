import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/models/shift_trade.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_shift_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_shift_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/shift_trade_controller.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_shift_grid.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_shift_screen.dart';
import 'package:spectrumstrategy/src/services/local_only_services.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';

import 'support/fake_scout_shift_sync_service.dart';
import 'support/fake_shift_trade_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

List<ScoutShiftRosterEntry> _roster(int count) => [
  for (var i = 0; i < count; i++)
    ScoutShiftRosterEntry(uid: 'u$i', name: 'Scouter $i'),
];

Future<EventController> _eventControllerWithMatches() async {
  const eventJson = '{"key":"2026miket","name":"Test","year":2026}';
  const matchesJson =
      '[{"key":"2026miket_qm1","event":"2026miket","match_number":1,'
      '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,254,1678]},'
      '"blue":{"team_keys":[118,2056,33]}}}]';

  Future<http.Response> api(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/event/2026miket')) {
      return http.Response(eventJson, 200);
    }
    if (path.endsWith('/matches')) {
      return http.Response(matchesJson, 200);
    }
    return http.Response('[]', 200);
  }

  final eventController = EventController(
    statboticsEnabled: true,
    client: StatboticsClient(httpClient: MockClient(api), sleep: (_) async {}),
  );
  await eventController.setEventKey('2026miket');
  return eventController;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'watchEvent switches subscriptions and reflects the emitted schedule',
    () async {
      final sync = FakeScoutShiftSyncService();
      final controller = ScoutShiftController(syncService: sync);
      addTearDown(controller.dispose);

      await controller.watchEvent('2026miket');
      expect(sync.watched, ['2026miket']);
      expect(controller.loading, isFalse);
      expect(controller.schedule, isNull);

      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      );
      sync.emit(schedule);
      await Future<void>.delayed(Duration.zero);
      expect(controller.schedule?.eventKey, '2026miket');
    },
  );

  test('generate applies the rotation locally then pushes it', () async {
    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    await controller.generate(matchCount: 12, roster: _roster(2));

    expect(controller.schedule, isNotNull);
    expect(controller.schedule!.rotations, hasLength(2));
    expect(sync.pushes.single.eventKey, '2026miket');
    expect(sync.pushes.single.authorUid, 'admin1');
  });

  test('editCell applies the edit locally then pushes it', () async {
    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');
    await controller.generate(matchCount: 12, roster: _roster(2));

    await controller.editCell(
      col: 0,
      match: 7,
      text: 'covering',
      color: ScheduleCellColor.grey,
    );

    expect(controller.schedule!.colorFor(0, 7), ScheduleCellColor.grey);
    expect(controller.schedule!.textFor(0, 7), 'covering');
    expect(sync.pushes.last.colorFor(0, 7), ScheduleCellColor.grey);
  });

  test('editCell is a no-op with no schedule yet', () async {
    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    await controller.editCell(
      col: 0,
      match: 1,
      text: 'x',
      color: ScheduleCellColor.red,
    );

    expect(controller.schedule, isNull);
    expect(sync.pushes, isEmpty);
  });

  test('renameColumn applies the rename locally then pushes it', () async {
    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');
    await controller.generate(matchCount: 12, roster: _roster(2));

    await controller.renameColumn(0, 'Alex');

    expect(controller.schedule!.roster[0].name, 'Alex');
    expect(controller.schedule!.rotations[0].name, 'Alex');
    expect(sync.pushes.last.roster[0].name, 'Alex');
  });

  test('renameColumn with a uid rebinds the column and pushes it', () async {
    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');
    await controller.generate(matchCount: 12, roster: _roster(2));

    await controller.renameColumn(0, 'Alex', uid: 'u9');

    expect(controller.schedule!.roster[0].uid, 'u9');
    expect(controller.schedule!.rotations[0].uid, 'u9');
    expect(sync.pushes.last.roster[0].uid, 'u9');
  });

  test('generate is a no-op with no event selected', () async {
    final sync = FakeScoutShiftSyncService();
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);

    await controller.generate(matchCount: 12, roster: _roster(2));

    expect(controller.schedule, isNull);
    expect(sync.pushes, isEmpty);
  });

  test(
    'generate with no signed-in user updates locally but does not push',
    () async {
      final sync = FakeScoutShiftSyncService(uid: '', displayName: '');
      final controller = ScoutShiftController(syncService: sync);
      addTearDown(controller.dispose);
      await controller.watchEvent('2026miket');

      await controller.generate(matchCount: 12, roster: _roster(2));

      expect(controller.schedule, isNotNull);
      expect(sync.pushes, isEmpty);
    },
  );

  test('pushes are serialized in call order even when one is laggy', () async {
    final sync = LaggyScoutShiftSyncService(
      uid: 'admin1',
      displayName: 'Admin',
    );
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    final first = controller.generate(matchCount: 6, roster: _roster(1));
    final second = controller.generate(matchCount: 12, roster: _roster(2));
    await Future.wait([first, second]);

    expect(sync.pushes, hasLength(2));
    expect(sync.pushes[0].matchCount, 6);
    expect(sync.pushes[1].matchCount, 12);
  });

  test(
    'a failed push does not block a later generate from going through',
    () async {
      final sync = FakeScoutShiftSyncService(
        uid: 'admin1',
        displayName: 'Admin',
      );
      final controller = ScoutShiftController(syncService: sync);
      addTearDown(controller.dispose);
      await controller.watchEvent('2026miket');

      sync.failNextPush = Exception('offline');
      await controller.generate(matchCount: 6, roster: _roster(1));
      expect(sync.pushes, isEmpty);
      expect(controller.failedWrites.hasFailures, isTrue);
      expect(controller.failedWrites.unlandedCount, 1);

      await controller.generate(matchCount: 12, roster: _roster(2));
      expect(sync.pushes, hasLength(1));
      expect(sync.pushes.single.matchCount, 12);
      expect(controller.failedWrites.hasFailures, isFalse);
    },
  );

  test('disposing the controller disposes its sync service', () {
    final sync = FakeScoutShiftSyncService();
    final controller = ScoutShiftController(syncService: sync);
    controller.dispose();
    expect(sync.disposed, isTrue);
  });

  test('model round-trips through JSON and derives per-scouter shifts', () {
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 12,
      roster: _roster(8),
      authorUid: 'admin1',
      authorDisplayName: 'Admin',
    );
    final decoded = ScoutShiftSchedule.fromJson(schedule.toJson());
    expect(decoded.rotationFor('u0')!.isOnDuty(1), isTrue);
    expect(decoded.rotationFor('u7')!.isOnDuty(1), isFalse);
    expect(decoded.rotationFor('u7')!.isOnDuty(7), isTrue);
  });

  test('Firestore service stamps the author and streams changes', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'admin1', displayName: 'Admin'),
    );
    addTearDown(auth.dispose);
    final service = FirestoreScoutShiftSyncService(
      authService: auth,
      firestore: firestore,
    );
    addTearDown(service.dispose);

    await service.push(
      ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      ),
    );

    final doc = await firestore
        .collection('scoutShifts')
        .doc('2026miket')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['authorUid'], 'admin1');
    expect(doc.data()!['authorDisplayName'], 'Admin');

    await service.watch('2026miket');
    final first = await service.scheduleStream.first;
    expect(first?.eventKey, '2026miket');
  });

  test('LocalOnlyScoutShiftSyncService is a no-op stub', () async {
    final service = LocalOnlyScoutShiftSyncService();

    expect(await service.scheduleStream.first, isNull);

    final controller = ScoutShiftController(syncService: service);
    await controller.watchEvent('2026miket');
    expect(controller.loading, isFalse);
    expect(controller.schedule, isNull);

    await service.push(
      ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 12,
        roster: _roster(2),
      ),
    );
    controller.dispose();
  });

  testWidgets('the screen builds without a controller and does not reach '
      'Firebase', (tester) async {
    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: EventController(statboticsEnabled: true),
          userRoleController: roles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ScoutShiftScreen), findsOneWidget);
  });

  testWidgets('a signed-in scouter sees their own upcoming shifts', (
    tester,
  ) async {
    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final eventController = EventController(statboticsEnabled: true);
    final sync = FakeScoutShiftSyncService(
      uid: 'local',
      displayName: 'Local user',
    );
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: controller,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Select an event'), findsOneWidget);
  });

  testWidgets('a failed push shows the pill', (tester) async {
    const eventJson = '{"key":"2026miket","name":"Test","year":2026}';
    const matchesJson =
        '[{"key":"2026miket_qm1","event":"2026miket","match_number":1,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,254,1678]},'
        '"blue":{"team_keys":[118,2056,33]}}}]';

    Future<http.Response> api(http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('/event/2026miket')) {
        return http.Response(eventJson, 200);
      }
      if (path.endsWith('/matches')) {
        return http.Response(matchesJson, 200);
      }
      return http.Response('[]', 200);
    }

    final eventController = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(eventController.dispose);
    await eventController.setEventKey('2026miket');

    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: controller,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('not saved'), findsNothing);

    sync.failNextPush = Exception('offline');
    await controller.generate(matchCount: 1, roster: _roster(1));
    await tester.pump();

    expect(find.text('1 edit not saved'), findsOneWidget);

    await controller.generate(matchCount: 1, roster: _roster(2));
    await tester.pump();

    expect(find.textContaining('not saved'), findsNothing);
  });

  testWidgets('the input names dialog parses one name per line and generates', (
    tester,
  ) async {
    const eventJson = '{"key":"2026miket","name":"Test","year":2026}';
    const matchesJson =
        '[{"key":"2026miket_qm1","event":"2026miket","match_number":1,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,254,1678]},'
        '"blue":{"team_keys":[118,2056,33]}}}]';

    Future<http.Response> api(http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('/event/2026miket')) {
        return http.Response(eventJson, 200);
      }
      if (path.endsWith('/matches')) {
        return http.Response(matchesJson, 200);
      }
      return http.Response('[]', 200);
    }

    final eventController = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(eventController.dispose);
    await eventController.setEventKey('2026miket');

    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: controller,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Input names'));
    await tester.pumpAndSettle();
    expect(find.text('Input names'), findsWidgets);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Ada Lovelace\nGrace Hopper');
    await tester.enterText(fields.at(1), '12');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(controller.schedule, isNotNull);
    expect(controller.schedule!.matchCount, 12);
    expect(controller.schedule!.roster.map((r) => r.name), [
      'Ada Lovelace',
      'Grace Hopper',
    ]);
  });

  testWidgets(
    'a name shared by two member profiles gets no uid and a warning',
    (tester) async {
      const eventJson = '{"key":"2026miket","name":"Test","year":2026}';
      const matchesJson =
          '[{"key":"2026miket_qm1","event":"2026miket","match_number":1,'
          '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,254,1678]},'
          '"blue":{"team_keys":[118,2056,33]}}}]';

      Future<http.Response> api(http.Request request) async {
        final path = request.url.path;
        if (path.endsWith('/event/2026miket')) {
          return http.Response(eventJson, 200);
        }
        if (path.endsWith('/matches')) {
          return http.Response(matchesJson, 200);
        }
        return http.Response('[]', 200);
      }

      final eventController = EventController(
        statboticsEnabled: true,
        client: StatboticsClient(
          httpClient: MockClient(api),
          sleep: (_) async {},
        ),
      );
      addTearDown(eventController.dispose);
      await eventController.setEventKey('2026miket');

      final roleService = FakeUserRoleService();
      roleService.setRole('local', UserRole.strategy);
      await roleService.fetchOrCreateProfile(
        uid: 'dup1',
        displayName: 'Sam Lee',
      );
      await roleService.fetchOrCreateProfile(
        uid: 'dup2',
        displayName: 'Sam Lee',
      );
      final auth = LocalOnlyAuthService();
      final roles = UserRoleController(
        authService: auth,
        roleService: roleService,
      );
      addTearDown(() async {
        roles.dispose();
        await auth.dispose();
      });
      await roles.bootstrap();

      final sync = FakeScoutShiftSyncService(
        uid: 'admin1',
        displayName: 'Admin',
      );
      final controller = ScoutShiftController(syncService: sync);
      addTearDown(controller.dispose);
      await controller.watchEvent('2026miket');

      await tester.pumpWidget(
        MaterialApp(
          home: ScoutShiftScreen(
            eventController: eventController,
            userRoleController: roles,
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Input names'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Sam Lee');
      await tester.enterText(fields.at(1), '6');
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(controller.schedule, isNotNull);
      expect(controller.schedule!.roster.single.name, 'Sam Lee');

      expect(controller.schedule!.roster.single.uid, isEmpty);
      expect(find.textContaining('Sam Lee'), findsWidgets);
      expect(
        find.textContaining('Name shared by several members'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cannot see their own shifts'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a roster name matching no account is named in the warning', (
    tester,
  ) async {
    final eventController = await _eventControllerWithMatches();
    addTearDown(eventController.dispose);

    final roleService = FakeUserRoleService();
    roleService.setRole('local', UserRole.strategy);
    await roleService.fetchOrCreateProfile(uid: 'u1', displayName: 'Sam Lee');
    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: roleService,
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Input names'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), 'Sammy');
    await tester.enterText(fields.at(1), '6');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(controller.schedule!.roster.single.uid, isEmpty);
    expect(find.textContaining('No matching account: Sammy'), findsOneWidget);
  });

  testWidgets('the input names dialog rejects a match count over 999', (
    tester,
  ) async {
    const eventJson = '{"key":"2026miket","name":"Test","year":2026}';
    const matchesJson =
        '[{"key":"2026miket_qm1","event":"2026miket","match_number":1,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,254,1678]},'
        '"blue":{"team_keys":[118,2056,33]}}}]';

    Future<http.Response> api(http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('/event/2026miket')) {
        return http.Response(eventJson, 200);
      }
      if (path.endsWith('/matches')) {
        return http.Response(matchesJson, 200);
      }
      return http.Response('[]', 200);
    }

    final eventController = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(eventController.dispose);
    await eventController.setEventKey('2026miket');

    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final sync = FakeScoutShiftSyncService(uid: 'admin1', displayName: 'Admin');
    final controller = ScoutShiftController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.watchEvent('2026miket');

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: controller,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Input names'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Ada Lovelace');
    await tester.enterText(fields.at(1), '1000');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot be more than 999'), findsOneWidget);
    expect(controller.schedule, isNull);

    await tester.enterText(fields.at(1), '999');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(controller.schedule, isNotNull);
    expect(controller.schedule!.matchCount, 999);
  });

  testWidgets(
    'resolved trade requests drop out of the list while a pending one stays '
    '(#1408)',
    (tester) async {
      final eventController = await _eventControllerWithMatches();
      addTearDown(eventController.dispose);

      final auth = LocalOnlyAuthService();
      final roles = UserRoleController(
        authService: auth,
        roleService: LocalUserRoleService(),
      );
      addTearDown(() async {
        roles.dispose();
        await auth.dispose();
      });
      await roles.bootstrap();

      final shiftSync = FakeScoutShiftSyncService(
        uid: 'admin1',
        displayName: 'Admin',
      );
      final shiftController = ScoutShiftController(syncService: shiftSync);
      addTearDown(shiftController.dispose);
      await shiftController.watchEvent('2026miket');
      await shiftController.generate(
        matchCount: 12,
        roster: [
          ScoutShiftRosterEntry(uid: 'local', name: 'Local user'),
          ScoutShiftRosterEntry(uid: 'other', name: 'Other scouter'),
        ],
      );

      final tradeSync = FakeShiftTradeSyncService(
        uid: 'local',
        displayName: 'Local user',
      );
      final tradeController = ShiftTradeController(syncService: tradeSync);
      addTearDown(tradeController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ScoutShiftScreen(
            eventController: eventController,
            userRoleController: roles,
            controller: shiftController,
            tradeController: tradeController,
          ),
        ),
      );
      await tester.pump();

      await tradeController.requestTrade(
        targetUid: 'other',
        targetDisplayName: 'Other scouter',
        requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      await tradeController.cancel(tradeController.trades.single);
      await tester.pump(Duration.zero);
      await tester.pump();

      await tradeController.requestTrade(
        targetUid: 'other',
        targetDisplayName: 'Other scouter',
        requesterBlock: const ScoutShiftBlock(startMatch: 7, endMatch: 12),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(tradeController.trades, hasLength(2));

      expect(
        find.textContaining('You asked Other scouter to cover matches 7'),
        findsOneWidget,
      );
      expect(
        find.textContaining('You asked Other scouter to cover matches 1'),
        findsNothing,
      );
      expect(find.text('1 pending'), findsOneWidget);
    },
  );

  testWidgets(
    'accepting a trade shows a confirmation and marks the traded block '
    '(#1455)',
    (tester) async {
      final eventController = await _eventControllerWithMatches();
      addTearDown(eventController.dispose);

      final auth = LocalOnlyAuthService();
      final roles = UserRoleController(
        authService: auth,
        roleService: LocalUserRoleService(),
      );
      addTearDown(() async {
        roles.dispose();
        await auth.dispose();
      });
      await roles.bootstrap();

      final shiftSync = FakeScoutShiftSyncService(
        uid: 'admin1',
        displayName: 'Admin',
      );
      final shiftController = ScoutShiftController(syncService: shiftSync);
      addTearDown(shiftController.dispose);
      await shiftController.watchEvent('2026miket');
      await shiftController.generate(
        matchCount: 12,
        roster: [
          ScoutShiftRosterEntry(uid: 'local', name: 'Local user'),
          ScoutShiftRosterEntry(uid: 'other', name: 'Other scouter'),
        ],
      );

      final tradeSync = FakeShiftTradeSyncService(
        uid: 'local',
        displayName: 'Local user',
      );
      final tradeController = ShiftTradeController(syncService: tradeSync);
      addTearDown(tradeController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ScoutShiftScreen(
            eventController: eventController,
            userRoleController: roles,
            controller: shiftController,
            tradeController: tradeController,
          ),
        ),
      );
      await tester.pump();

      await tradeSync.create(
        ShiftTrade(
          id: 't1',
          eventKey: '2026miket',
          requesterUid: 'other',
          requesterDisplayName: 'Other scouter',
          targetUid: 'local',
          targetDisplayName: 'Local user',
          requesterBlock: const ScoutShiftBlock(startMatch: 7, endMatch: 12),
        ),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(
        find.text('Trade accepted -- your shifts updated.'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Traded with Other scouter',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('the trade requests section stays bounded so the schedule stays '
      'reachable with many pending requests (#1408)', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final eventController = await _eventControllerWithMatches();
    addTearDown(eventController.dispose);

    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final shiftSync = FakeScoutShiftSyncService(
      uid: 'admin1',
      displayName: 'Admin',
    );
    final shiftController = ScoutShiftController(syncService: shiftSync);
    addTearDown(shiftController.dispose);
    await shiftController.watchEvent('2026miket');
    await shiftController.generate(
      matchCount: 12,
      roster: [ScoutShiftRosterEntry(uid: 'local', name: 'Local user')],
    );

    final tradeSync = FakeShiftTradeSyncService(
      uid: 'local',
      displayName: 'Local user',
    );
    final tradeController = ShiftTradeController(syncService: tradeSync);
    addTearDown(tradeController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: shiftController,
          tradeController: tradeController,
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 30; i++) {
      await tradeController.requestTrade(
        targetUid: 'target-$i',
        targetDisplayName: 'Target $i',
        requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 1),
      );
    }
    await tester.pump(Duration.zero);
    await tester.pump();

    expect(tradeController.trades, hasLength(30));

    expect(tester.takeException(), isNull);
    expect(find.byType(ScoutShiftGrid), findsOneWidget);
    expect(tester.getSize(find.byType(ScoutShiftGrid)).height, greaterThan(0));
    final listSize = tester.getSize(
      find.byKey(const ValueKey('trade_requests_list')),
    );
    expect(listSize.height, lessThanOrEqualTo(320));
  });

  testWidgets(
    'a scouter whose account matches no column is told why trading is '
    'missing',
    (tester) async {
      final eventController = await _eventControllerWithMatches();
      addTearDown(eventController.dispose);

      final auth = LocalOnlyAuthService();
      final roles = UserRoleController(
        authService: auth,
        roleService: LocalUserRoleService(),
      );
      addTearDown(() async {
        roles.dispose();
        await auth.dispose();
      });
      await roles.bootstrap();

      final shiftSync = FakeScoutShiftSyncService(
        uid: 'admin1',
        displayName: 'Admin',
      );
      final shiftController = ScoutShiftController(syncService: shiftSync);
      addTearDown(shiftController.dispose);
      await shiftController.watchEvent('2026miket');

      await shiftController.generate(
        matchCount: 12,
        roster: const [
          ScoutShiftRosterEntry(uid: '', name: 'Local user'),
          ScoutShiftRosterEntry(uid: '', name: 'Other scouter'),
        ],
      );

      final tradeSync = FakeShiftTradeSyncService(
        uid: 'local',
        displayName: 'Local user',
      );
      final tradeController = ShiftTradeController(syncService: tradeSync);
      addTearDown(tradeController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ScoutShiftScreen(
            eventController: eventController,
            userRoleController: roles,
            controller: shiftController,
            tradeController: tradeController,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Request trade'), findsNothing);
      expect(
        find.textContaining('No column on this rotation is linked'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a linked scouter gets the trade button and no notice', (
    tester,
  ) async {
    final eventController = await _eventControllerWithMatches();
    addTearDown(eventController.dispose);

    final auth = LocalOnlyAuthService();
    final roles = UserRoleController(
      authService: auth,
      roleService: LocalUserRoleService(),
    );
    addTearDown(() async {
      roles.dispose();
      await auth.dispose();
    });
    await roles.bootstrap();

    final shiftSync = FakeScoutShiftSyncService(
      uid: 'admin1',
      displayName: 'Admin',
    );
    final shiftController = ScoutShiftController(syncService: shiftSync);
    addTearDown(shiftController.dispose);
    await shiftController.watchEvent('2026miket');
    await shiftController.generate(
      matchCount: 12,
      roster: const [
        ScoutShiftRosterEntry(uid: 'local', name: 'Local user'),
        ScoutShiftRosterEntry(uid: 'other', name: 'Other scouter'),
      ],
    );

    final tradeSync = FakeShiftTradeSyncService(
      uid: 'local',
      displayName: 'Local user',
    );
    final tradeController = ShiftTradeController(syncService: tradeSync);
    addTearDown(tradeController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: shiftController,
          tradeController: tradeController,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Request trade'), findsOneWidget);
    expect(
      find.textContaining('No column on this rotation is linked'),
      findsNothing,
    );
  });
}
