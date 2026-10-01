import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_shift_mirror.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_shift_mirror_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_shift_controller.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_shift_screen.dart';
import 'package:spectrumstrategy/src/services/local_only_services.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';

import 'support/fake_pit_shift_mirror_sync_service.dart';
import 'support/fake_scout_shift_sync_service.dart';

PitShiftMirror _mirror({List<MirroredPitShift>? shifts}) => PitShiftMirror(
  eventKey: '2026miket',
  competition: 'Kettering',
  syncedAt: DateTime.utc(2026, 3, 14, 6, 10),
  shifts:
      shifts ??
      [
        const MirroredPitShift(
          id: 'a',
          label: 'Load in',
          kind: 'loadIn',
          assignees: [MirroredAssignee(name: 'Local user', uid: 'local')],
        ),
        const MirroredPitShift(
          id: 'b',
          label: 'Pit duty',
          kind: 'pitDuty',
          assignees: [
            MirroredAssignee(name: 'Ada Lovelace', uid: 'u-ada'),
            MirroredAssignee(name: 'Unlinked Person'),
          ],
          startMatch: 1,
          endMatch: 20,
        ),
      ],
);

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
    client: StatboticsClient(httpClient: MockClient(api), sleep: (_) async {}),
  );
  await eventController.setEventKey('2026miket');
  return eventController;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('MirroredPitShift', () {
    test('rangeText prefers the match range and collapses a single match', () {
      const block = MirroredPitShift(
        id: 'x',
        label: 'L',
        kind: 'matchBlock',
        assignees: [],
        startMatch: 3,
        endMatch: 9,
      );
      expect(block.rangeText(), 'Q3-9');
      const single = MirroredPitShift(
        id: 'y',
        label: 'L',
        kind: 'matchBlock',
        assignees: [],
        startMatch: 12,
        endMatch: 12,
      );
      expect(single.rangeText(), 'Q12');
    });

    test('rangeText renders a wall-clock range in local time', () {
      final shift = MirroredPitShift(
        id: 'x',
        label: 'Load in',
        kind: 'loadIn',
        assignees: const [],
        startsAt: DateTime(2026, 3, 13, 7, 0),
        endsAt: DateTime(2026, 3, 13, 12, 30),
      );
      expect(shift.rangeText(), '7:00 am-12:30 pm');
    });

    test('rangeText is empty when the shift has neither range', () {
      const shift = MirroredPitShift(
        id: 'x',
        label: 'L',
        kind: 'unavailable',
        assignees: [],
      );
      expect(shift.rangeText(), '');
    });
  });

  group('PitShiftMirror', () {
    test('round-trips through json and omits absent fields', () {
      final mirror = _mirror();
      final json = mirror.toJson();
      final shifts = json['shifts'] as List<dynamic>;
      expect((shifts[0] as Map).containsKey('startMatch'), isFalse);
      expect((shifts[0] as Map).containsKey('startsAt'), isFalse);
      expect(((shifts[1] as Map)['assignees'] as List)[1], {
        'name': 'Unlinked Person',
      });

      final back = PitShiftMirror.fromJson(json);
      expect(back.toJson(), json);
      expect(back.syncedAt, DateTime.utc(2026, 3, 14, 6, 10));
    });

    test('shiftsFor matches on the translated uid only', () {
      final mirror = _mirror();
      expect(mirror.shiftsFor('local').map((s) => s.id), ['a']);
      expect(mirror.shiftsFor('u-ada').map((s) => s.id), ['b']);
      expect(mirror.shiftsFor('nobody'), isEmpty);
    });

    test('fromJson tolerates a document with missing fields', () {
      final mirror = PitShiftMirror.fromJson(<String, dynamic>{});
      expect(mirror.eventKey, '');
      expect(mirror.isEmpty, isTrue);
      expect(mirror.syncedAt.millisecondsSinceEpoch, 0);
    });
  });

  group('PitShiftMirrorController', () {
    test('watchEvent subscribes once and reflects later snapshots', () async {
      final sync = FakePitShiftMirrorSyncService();
      final controller = PitShiftMirrorController(syncService: sync);
      addTearDown(controller.dispose);

      await controller.watchEvent('2026miket');
      await Future<void>.delayed(Duration.zero);
      expect(sync.watched, ['2026miket']);
      expect(controller.mirror, isNull);

      var notified = 0;
      controller.addListener(() => notified++);
      sync.emit(_mirror());
      await Future<void>.delayed(Duration.zero);
      expect(controller.mirror?.competition, 'Kettering');
      expect(notified, 1);

      await controller.watchEvent('2026miket');
      expect(sync.watched, ['2026miket']);
      expect(controller.mirror, isNotNull);

      await controller.watchEvent('2026txcmp');
      expect(sync.watched, ['2026miket', '2026txcmp']);
      expect(controller.mirror, isNull);
    });

    test('dispose disposes the sync service', () async {
      final sync = FakePitShiftMirrorSyncService();
      final controller = PitShiftMirrorController(syncService: sync);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(sync.disposed, isTrue);
    });
  });

  testWidgets('the pit schedule section summarises and lists mirrored shifts', (
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

    final eventController = await _eventControllerWithMatches();
    addTearDown(eventController.dispose);

    final shiftSync =
        FakeScoutShiftSyncService(uid: 'local', displayName: 'Local user')
          ..stored = ScoutShiftSchedule.generate(
            eventKey: '2026miket',
            matchCount: 1,
            roster: const [
              ScoutShiftRosterEntry(uid: 'local', name: 'Local user'),
            ],
            authorUid: 'local',
            authorDisplayName: 'Local user',
          );
    final shiftController = ScoutShiftController(syncService: shiftSync);
    addTearDown(shiftController.dispose);

    final mirrorSync = FakePitShiftMirrorSyncService()..stored = _mirror();
    final mirrorController = PitShiftMirrorController(syncService: mirrorSync);
    addTearDown(mirrorController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: shiftController,
          pitMirrorController: mirrorController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(mirrorSync.watched, ['2026miket']);
    expect(find.text('Pit schedule'), findsOneWidget);
    expect(find.textContaining('2 shifts, 1 yours, synced'), findsOneWidget);

    expect(find.text('Load in'), findsNothing);

    await tester.tap(find.text('Pit schedule'));
    await tester.pumpAndSettle();

    expect(find.text('Load in'), findsOneWidget);
    expect(find.text('Pit duty'), findsOneWidget);
    expect(find.text('Q1-20'), findsOneWidget);
    expect(find.text('Ada Lovelace, Unlinked Person'), findsOneWidget);
  });

  testWidgets('the pit schedule shows even before a scouting rotation exists', (
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

    final eventController = await _eventControllerWithMatches();
    addTearDown(eventController.dispose);

    final shiftController = ScoutShiftController(
      syncService: FakeScoutShiftSyncService(),
    );
    addTearDown(shiftController.dispose);

    final mirrorSync = FakePitShiftMirrorSyncService()..stored = _mirror();
    final mirrorController = PitShiftMirrorController(syncService: mirrorSync);
    addTearDown(mirrorController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: shiftController,
          pitMirrorController: mirrorController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No schedule yet'), findsOneWidget);
    expect(find.text('Pit schedule'), findsOneWidget);
  });

  testWidgets('no mirror document hides the pit section', (tester) async {
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

    final eventController = await _eventControllerWithMatches();
    addTearDown(eventController.dispose);

    final shiftController = ScoutShiftController(
      syncService: FakeScoutShiftSyncService(),
    );
    addTearDown(shiftController.dispose);

    final mirrorController = PitShiftMirrorController(
      syncService: FakePitShiftMirrorSyncService(),
    );
    addTearDown(mirrorController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ScoutShiftScreen(
          eventController: eventController,
          userRoleController: roles,
          controller: shiftController,
          pitMirrorController: mirrorController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pit schedule'), findsNothing);
  });
}
