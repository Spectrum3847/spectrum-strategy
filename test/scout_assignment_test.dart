import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_assignment_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_assignment_controller.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_assignments_screen.dart';
import 'package:spectrumstrategy/src/services/local_only_services.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';

import 'support/fake_spectrum_auth_service.dart';

class _FakeSyncService implements ScoutAssignmentSyncService {
  final _controller = StreamController<List<ScoutAssignment>>.broadcast();
  final List<ScoutAssignment> upserts = <ScoutAssignment>[];
  final List<String> deletes = <String>[];

  void emit(List<ScoutAssignment> items) => _controller.add(items);

  @override
  Stream<List<ScoutAssignment>> watchAll() => _controller.stream;

  @override
  Future<void> upsert(ScoutAssignment assignment) async =>
      upserts.add(assignment);

  @override
  Future<void> delete(String id) async => deletes.add(id);

  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}

void main() {
  test('model round-trips through JSON and derives a stable id', () {
    final a = ScoutAssignment(
      id: ScoutAssignment.idFor('2024casj_qm12', 'blue2'),
      matchKey: '2024casj_qm12',
      matchNumber: 12,
      station: 'blue2',
      scouterUid: 'u1',
      scouterName: 'Scout One',
      authorUid: 'admin1',
      authorDisplayName: 'Admin',
    );
    expect(a.id, '2024casj_qm12__blue2');
    expect(a.isRed, isFalse);

    final decoded = ScoutAssignment.fromJson(a.toJson());
    expect(decoded.matchKey, a.matchKey);
    expect(decoded.station, 'blue2');
    expect(decoded.scouterUid, 'u1');
    expect(decoded.authorUid, 'admin1');
    expect(decoded.matchNumber, 12);
  });

  test('controller filters by match and by scouter', () async {
    final sync = _FakeSyncService();
    final controller = ScoutAssignmentController(syncService: sync);
    addTearDown(controller.dispose);
    controller.start();

    sync.emit([
      ScoutAssignment(
        id: ScoutAssignment.idFor('qm1', 'red1'),
        matchKey: 'qm1',
        matchNumber: 1,
        station: 'red1',
        scouterUid: 'u1',
        scouterName: 'A',
      ),
      ScoutAssignment(
        id: ScoutAssignment.idFor('qm2', 'blue3'),
        matchKey: 'qm2',
        matchNumber: 2,
        station: 'blue3',
        scouterUid: 'u1',
        scouterName: 'A',
      ),
      ScoutAssignment(
        id: ScoutAssignment.idFor('qm1', 'blue1'),
        matchKey: 'qm1',
        matchNumber: 1,
        station: 'blue1',
        scouterUid: 'u2',
        scouterName: 'B',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.loading, isFalse);
    expect(controller.forMatch('qm1').length, 2);

    expect(controller.forMatch('qm1').first.station, 'red1');
    final mine = controller.forScouter('u1');
    expect(mine.map((a) => a.matchNumber), [1, 2]);
  });

  test('assign and unassign forward to the sync service', () async {
    final sync = _FakeSyncService();
    final controller = ScoutAssignmentController(syncService: sync);
    addTearDown(controller.dispose);

    await controller.assign(
      matchKey: 'qm5',
      matchNumber: 5,
      station: 'red3',
      scouterUid: 'u9',
      scouterName: 'Nine',
    );
    expect(sync.upserts.single.id, 'qm5__red3');
    expect(sync.upserts.single.scouterUid, 'u9');

    await controller.unassign('qm5', 'red3');
    expect(sync.deletes.single, 'qm5__red3');
  });

  test('Firestore service stamps the author and streams changes', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'admin1', displayName: 'Admin'),
    );
    addTearDown(auth.dispose);
    final service = FirestoreScoutAssignmentSyncService(
      authService: auth,
      firestore: firestore,
    );

    await service.upsert(
      ScoutAssignment(
        id: ScoutAssignment.idFor('qm7', 'red1'),
        matchKey: 'qm7',
        matchNumber: 7,
        station: 'red1',
        scouterUid: 'u3',
        scouterName: 'Three',
      ),
    );

    final doc = await firestore
        .collection('scoutAssignments')
        .doc('qm7__red1')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['authorUid'], 'admin1');
    expect(doc.data()!['authorDisplayName'], 'Admin');
    expect(doc.data()!['scouterUid'], 'u3');

    final first = await service.watchAll().first;
    expect(first.single.station, 'red1');
  });

  test('LocalOnlyScoutAssignmentSyncService is a no-op stub', () async {
    final service = LocalOnlyScoutAssignmentSyncService();

    expect(await service.watchAll().single, isEmpty);

    final controller = ScoutAssignmentController(syncService: service);
    controller.start();
    await pumpEventQueue();
    expect(controller.loading, isFalse);
    expect(controller.assignments, isEmpty);

    await service.upsert(
      ScoutAssignment(
        id: ScoutAssignment.idFor('qm1', 'red1'),
        matchKey: 'qm1',
        matchNumber: 1,
        station: 'red1',
        scouterUid: 'u1',
        scouterName: 'A',
      ),
    );
    await service.delete('qm1__red1');
  });

  test('disposing the controller disposes its sync service', () {
    final sync = _FakeSyncService();
    final controller = ScoutAssignmentController(syncService: sync);
    controller.start();
    controller.dispose();
    expect(sync.disposed, isTrue);
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
        home: ScoutAssignmentsScreen(
          eventController: EventController(),
          userRoleController: roles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ScoutAssignmentsScreen), findsOneWidget);
  });
}
