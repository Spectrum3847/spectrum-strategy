import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import 'support/fake_spectrum_auth_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeSpectrumAuthService auth;
  late FirestoreScoutingSyncService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = FakeSpectrumAuthService();
    service = FirestoreScoutingSyncService(
      authService: auth,
      firestore: firestore,
    );
  });

  tearDown(() async {
    await service.dispose();
    await auth.dispose();
  });

  test('initialize without a signed-in user reports signedOut', () async {
    await service.initialize();
    expect(service.status.state, ScoutingSyncState.signedOut);
  });

  test('initialize after sign-in subscribes to the central scoutEntries collection', () async {
    auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'u-1', displayName: 'Scout A'),
    );
    service = FirestoreScoutingSyncService(
      authService: auth,
      firestore: firestore,
    );

    await firestore
        .collection('scoutEntries')
        .doc('seed-1')
        .set(
          ScoutEntry(
            id: 'seed-1',
            matchId: 'match-1',
            teamNumber: 254,
            authorUid: 'u-2',
            authorDisplayName: 'Scout B',
          ).toJson(),
        );

    final completer = Completer<List<ScoutEntry>>();
    final sub = service.remoteEntriesStream.listen((entries) {
      if (!completer.isCompleted) {
        completer.complete(entries);
      }
    });

    await service.initialize();
    final received = await completer.future.timeout(const Duration(seconds: 2));
    await sub.cancel();

    expect(received, hasLength(1));
    expect(received.first.teamNumber, 254);
    expect(received.first.authorUid, 'u-2');
    expect(service.status.state, ScoutingSyncState.synced);
  });

  test('push stamps authorUid + displayName from the signed-in user', () async {
    auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'u-7', displayName: 'scouter one'),
    );
    service = FirestoreScoutingSyncService(
      authService: auth,
      firestore: firestore,
    );
    await service.initialize();

    final entry = ScoutEntry(
      id: 'entry-1',
      matchId: 'match-1',
      teamNumber: 3847,
      alliance: 'Blue',
      byPhase: <StrategyPhase, ScoutPhaseData>{
        StrategyPhase.teleop: const ScoutPhaseData(score: 12),
      },
    );
    await service.push(entry);

    final doc = await firestore.collection('scoutEntries').doc('entry-1').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['authorUid'], 'u-7');
    expect(doc.data()!['authorDisplayName'], 'scouter one');
    expect(doc.data()!['teamNumber'], 3847);
  });

  test(
    'push preserves original authorUid when entry already has one',
    () async {
      auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'admin-1', displayName: 'Admin'),
      );
      service = FirestoreScoutingSyncService(
        authService: auth,
        firestore: firestore,
      );
      await service.initialize();

      final entry = ScoutEntry(
        id: 'entry-2',
        matchId: 'match-1',
        teamNumber: 254,
        authorUid: 'scout-42',
        authorDisplayName: 'Original Scout',
      );
      await service.push(entry);

      final doc = await firestore
          .collection('scoutEntries')
          .doc('entry-2')
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['authorUid'], 'scout-42');
      expect(doc.data()!['authorDisplayName'], 'Original Scout');
    },
  );

  test('push writes updatedAtTs as a Firestore timestamp', () async {
    auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'u-7', displayName: 'scouter one'),
    );
    service = FirestoreScoutingSyncService(
      authService: auth,
      firestore: firestore,
    );
    await service.initialize();

    final updatedAt = DateTime.utc(2026, 4, 5, 12, 30);
    await service.push(
      ScoutEntry(
        id: 'entry-ts',
        matchId: 'match-1',
        teamNumber: 3847,
        updatedAt: updatedAt,
      ),
    );

    final doc = await firestore
        .collection('scoutEntries')
        .doc('entry-ts')
        .get();
    final ts = doc.data()!['updatedAtTs'];
    expect(ts, isA<Timestamp>());
    expect((ts as Timestamp).toDate().toUtc(), updatedAt);
  });

  test(
    'decode orders by updatedAtTs, not a poisoned updatedAt string',
    () async {
      auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'u-1', displayName: 'Scout A'),
      );
      service = FirestoreScoutingSyncService(
        authService: auth,
        firestore: firestore,
      );

      final realTime = DateTime.utc(2026, 4, 5, 12, 30);
      await firestore.collection('scoutEntries').doc('poisoned').set(
        <String, dynamic>{
          ...ScoutEntry(
            id: 'poisoned',
            matchId: 'match-1',
            teamNumber: 254,
            authorUid: 'u-2',
            authorDisplayName: 'Scout B',
            updatedAt: DateTime.utc(2099, 1, 1),
          ).toJson(),
          'updatedAtTs': Timestamp.fromDate(realTime),
        },
      );

      final completer = Completer<List<ScoutEntry>>();
      final sub = service.remoteEntriesStream.listen((entries) {
        if (entries.isNotEmpty && !completer.isCompleted) {
          completer.complete(entries);
        }
      });
      await service.initialize();
      final received = await completer.future.timeout(
        const Duration(seconds: 2),
      );
      await sub.cancel();

      expect(received, hasLength(1));

      expect(received.first.updatedAt, realTime);
    },
  );

  test('push without a signed-in user is a no-op', () async {
    await service.initialize();
    final entry = ScoutEntry(id: 'x', matchId: 'm', teamNumber: 1);
    await service.push(entry);

    final docs = await firestore.collection('scoutEntries').get();
    expect(docs.docs, isEmpty);
  });

  test(
    'delete forwards any entry to Firestore (authorization enforced by rules)',
    () async {
      auth = FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'u-7', displayName: 'scouter one'),
      );
      service = FirestoreScoutingSyncService(
        authService: auth,
        firestore: firestore,
      );
      await service.initialize();

      await firestore
          .collection('scoutEntries')
          .doc('mine')
          .set(
            ScoutEntry(
              id: 'mine',
              matchId: 'match-1',
              teamNumber: 254,
              authorUid: 'u-7',
              authorDisplayName: 'scouter one',
            ).toJson(),
          );
      await firestore
          .collection('scoutEntries')
          .doc('theirs')
          .set(
            ScoutEntry(
              id: 'theirs',
              matchId: 'match-1',
              teamNumber: 255,
              authorUid: 'u-other',
              authorDisplayName: 'Other Scout',
            ).toJson(),
          );

      await service.delete(
        ScoutEntry(
          id: 'mine',
          matchId: 'match-1',
          teamNumber: 254,
          authorUid: 'u-7',
          authorDisplayName: 'scouter one',
        ),
      );
      await service.delete(
        ScoutEntry(
          id: 'theirs',
          matchId: 'match-1',
          teamNumber: 255,
          authorUid: 'u-other',
          authorDisplayName: 'Other Scout',
        ),
      );

      final mine = await firestore.collection('scoutEntries').doc('mine').get();
      final theirs = await firestore
          .collection('scoutEntries')
          .doc('theirs')
          .get();
      expect(mine.exists, isFalse);
      expect(theirs.exists, isFalse);
    },
  );

  test('sign-out drops the remote subscription', () async {
    auth = FakeSpectrumAuthService(
      initialUser: const SpectrumUser(uid: 'u-1', displayName: 'Scout A'),
    );
    service = FirestoreScoutingSyncService(
      authService: auth,
      firestore: firestore,
    );
    await service.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(service.status.state, ScoutingSyncState.synced);

    auth.emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
    await Future<void>.delayed(Duration.zero);
    expect(service.status.state, ScoutingSyncState.signedOut);
  });
}
