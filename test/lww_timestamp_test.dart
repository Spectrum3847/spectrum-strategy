import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_assignment_sync_service.dart';
import 'package:spectrumstrategy/src/services/pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_spectrum_auth_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeSpectrumAuthService auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'u-1', displayName: 'Strategist'),
    );
  });

  group('FirestorePickListSyncService', () {
    test('push and team ops write updatedAtTs as a timestamp', () async {
      final service = FirestorePickListSyncService(
        authService: auth,
        firestore: firestore,
      );
      final updatedAt = DateTime.utc(2026, 7, 8, 12);
      final list = PickList(
        id: 'l1',
        name: 'First pick',
        teamNumbers: const [3847],
        updatedAt: updatedAt,
      );

      await service.push(list);
      var doc = await firestore.collection('pickLists').doc('l1').get();
      var ts = doc.data()!['updatedAtTs'];
      expect(ts, isA<Timestamp>());
      expect((ts as Timestamp).toDate().toUtc(), updatedAt);

      final reordered = list.copyWith(
        teamNumbers: const [3847, 118],
        updatedAt: DateTime.utc(2026, 7, 8, 13),
      );
      await service.pushTeamAdd(reordered, 118);
      doc = await firestore.collection('pickLists').doc('l1').get();
      ts = doc.data()!['updatedAtTs'];
      expect(ts, isA<Timestamp>());
      expect((ts as Timestamp).toDate().toUtc(), DateTime.utc(2026, 7, 8, 13));
    });

    test('decode orders by updatedAtTs, not a poisoned string', () async {
      final realTime = DateTime.utc(2026, 7, 8, 12);
      await firestore.collection('pickLists').doc('poisoned').set({
        ...PickList(
          id: 'poisoned',
          name: 'Frozen list',
          teamNumbers: const [254],
          updatedAt: DateTime.utc(2099, 1, 1),
        ).toJson(),
        'updatedAtTs': Timestamp.fromDate(realTime),
      });
      final service = FirestorePickListSyncService(
        authService: auth,
        firestore: firestore,
      );

      final remote = service.remoteListsStream.first;
      await service.syncNow();
      expect((await remote).single.updatedAt, realTime);
    });
  });

  group('FirestorePitScoutingSyncService', () {
    test('push writes updatedAtTs as a timestamp', () async {
      final service = FirestorePitScoutingSyncService(
        authService: auth,
        firestore: firestore,
      );
      final updatedAt = DateTime.utc(2026, 7, 8, 9);
      await service.push(
        PitScoutEntry(id: 'p1', teamNumber: 3847, updatedAt: updatedAt),
      );

      final doc = await firestore.collection('pitScoutEntries').doc('p1').get();
      final ts = doc.data()!['updatedAtTs'];
      expect(ts, isA<Timestamp>());
      expect((ts as Timestamp).toDate().toUtc(), updatedAt);
    });

    test('decode orders by updatedAtTs, not a poisoned string', () async {
      final realTime = DateTime.utc(2026, 7, 8, 9);
      await firestore.collection('pitScoutEntries').doc('p2').set({
        ...PitScoutEntry(
          id: 'p2',
          teamNumber: 118,
          updatedAt: DateTime.utc(2099, 1, 1),
        ).toJson(),
        'updatedAtTs': Timestamp.fromDate(realTime),
      });
      final service = FirestorePitScoutingSyncService(
        authService: auth,
        firestore: firestore,
      );

      final remote = service.remoteEntriesStream.first;
      await service.syncNow();
      expect((await remote).single.updatedAt, realTime);
    });
  });

  group('FirestoreScoutAssignmentSyncService', () {
    test('upsert writes updatedAtTs; watchAll orders by it', () async {
      final service = FirestoreScoutAssignmentSyncService(
        authService: auth,
        firestore: firestore,
      );
      await service.upsert(
        ScoutAssignment(
          id: 'a1',
          matchKey: '2026test_qm1',
          matchNumber: 1,
          station: 'red1',
          scouterUid: 'scout-1',
          scouterName: 'Scout',
        ),
      );

      final doc = await firestore
          .collection('scoutAssignments')
          .doc('a1')
          .get();
      expect(doc.data()!['updatedAtTs'], isA<Timestamp>());

      final realTime = DateTime.utc(2026, 7, 8, 10);
      await firestore.collection('scoutAssignments').doc('a1').set({
        ...doc.data()!,
        'updatedAt': '2099-01-01T00:00:00.000Z',
        'updatedAtTs': Timestamp.fromDate(realTime),
      });
      final assignments = await service.watchAll().first;
      expect(assignments.single.updatedAt, realTime);
    });
  });
}
