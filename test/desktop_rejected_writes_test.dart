import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_pit_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_prescouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/services/desktop_pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/services/desktop_post_match_report_sync_service.dart';
import 'package:spectrumstrategy/src/services/desktop_strategy_board_sync_service.dart';
import 'package:spectrumstrategy/src/services/desktop_trex_trait_report_sync_service.dart';
import 'package:spectrumstrategy/src/services/rejected_writes.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_pending_push_queue.dart';
import 'support/fake_pick_list_storage.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_prescouting_storage.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_trex_trait_report_storage.dart';

class _Firestore extends fc.Firestore {
  _Firestore() : super(projectId: 'test', idTokenProvider: _token);

  static Future<String?> _token() async => 'token';

  int? failStatus;
  int writes = 0;
  List<fc.Document> remote = <fc.Document>[];

  void _write() {
    writes++;
    final status = failStatus;
    if (status != null) throw fc.FirestoreApiException(status, 'refused');
  }

  @override
  Future<fc.Document> setDocument(
    String path,
    Map<String, dynamic> fields, {
    List<String>? updateMask,
  }) async {
    _write();
    return fc.Document(name: path, fields: fields);
  }

  @override
  Future<void> deleteDocument(String path) async => _write();

  @override
  Future<List<fc.Document>> listDocuments(
    String path, {
    int pageSize = 300,
  }) async => remote;

  @override
  Future<List<fc.Document>> runQuery(
    String collection, {
    List<fc.FieldFilter> filters = const <fc.FieldFilter>[],
    String? orderBy,
    bool descending = false,
    int? limit,
  }) async => remote;
}

class _Subject {
  const _Subject({
    required this.id,
    required this.collection,
    required this.push,
    required this.syncNow,
    required this.state,
    this.delete,
  });

  final String id;
  final String collection;
  final Future<void> Function() push;
  final Future<void> Function()? delete;
  final Future<void> Function() syncNow;
  final String Function() state;
}

class _Case {
  const _Case(this.name, this.build);

  final String name;
  final Future<_Subject> Function(_Firestore, FakePendingPushQueue) build;
}

const SpectrumUser _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

FakeSpectrumAuthService _auth() => FakeSpectrumAuthService(initialUser: _user);

const Set<String> _withoutDelete = {'post-match reports'};

final List<_Case> _cases = <_Case>[
  _Case('scout entries', (firestore, queue) async {
    final entry = ScoutEntry(id: 'e1', matchId: 'Q1', teamNumber: 3847);
    final storage = FakeScoutingStorage();
    await storage.saveEntry(entry);
    final service = DesktopScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: entry.id,
      collection: 'scoutEntries',
      push: () => service.push(entry),
      delete: () => service.delete(entry),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
  _Case('pit scout entries', (firestore, queue) async {
    final entry = PitScoutEntry(id: 'p1', teamNumber: 3847);
    final storage = FakePitScoutingStorage();
    await storage.saveEntry(entry);
    final service = DesktopPitScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: entry.id,
      collection: 'pitScoutEntries',
      push: () => service.push(entry),
      delete: () => service.delete(entry),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
  _Case('prescout entries', (firestore, queue) async {
    final entry = PrescoutEntry(id: 'ps1', teamNumber: 3847);
    final storage = FakePrescoutingStorage();
    await storage.saveEntry(entry);
    final service = DesktopPrescoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: entry.id,
      collection: 'prescoutEntries',
      push: () => service.push(entry),
      delete: () => service.delete(entry),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
  _Case('pick lists', (firestore, queue) async {
    final list = PickList(
      id: 'l1',
      name: 'First pick',
      teamNumbers: const [3847],
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );
    final storage = FakePickListStorage();
    await storage.save(list);
    final service = DesktopPickListSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: list.id,
      collection: 'pickLists',
      push: () => service.push(list),
      delete: () => service.delete(list),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
  _Case('strategy boards', (firestore, queue) async {
    final board = StrategySession.create(id: 'b1');
    final directory = FakeMatchDirectory();
    await directory.saveMatch(board);
    final service = DesktopStrategyBoardSyncService(
      authService: _auth(),
      firestore: firestore,
      directory: directory,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: board.id,
      collection: 'strategyBoards',
      push: () => service.push(board),
      delete: () => service.delete(board),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
  _Case('post-match reports', (firestore, queue) async {
    final report = PostMatchReport(
      id: 'r1',
      eventKey: '2026txhou',
      matchId: 'qm1',
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );
    final storage = FakePostMatchReportStorage();
    await storage.saveReport(report);
    final service = DesktopPostMatchReportSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: report.id,
      collection: 'postMatchReports',
      push: () => service.push(report),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
  _Case('trait reports', (firestore, queue) async {
    final report = TrexTraitReport(
      id: 't1',
      trait: 'defense',
      teamNumber: 3847,
      matchNumber: 1,
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );
    final storage = FakeTrexTraitReportStorage();
    await storage.saveReport(report);
    final service = DesktopTrexTraitReportSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);
    return _Subject(
      id: report.id,
      collection: 'trexTraitReports',
      push: () => service.push(report),
      delete: () => service.delete(report),
      syncNow: service.syncNow,
      state: () => service.status.state.name,
    );
  }),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final testCase in _cases) {
    group(testCase.name, () {
      late _Firestore firestore;
      late FakePendingPushQueue queue;
      late _Subject subject;

      setUp(() async {
        firestore = _Firestore();
        queue = FakePendingPushQueue();
        subject = await testCase.build(firestore, queue);
      });

      test('a refused write is not retried and stays rejected', () async {
        firestore.failStatus = 403;
        await subject.push();
        expect(subject.state(), 'rejected');
        expect(await queue.pending(subject.collection), isEmpty);

        await subject.syncNow();
        await subject.syncNow();

        expect(firestore.writes, 1);
        expect(subject.state(), 'rejected');
      });

      test('a transient failure is retried on the next poll', () async {
        firestore.failStatus = 503;
        await subject.push();
        expect(subject.state(), 'offline');
        expect(await queue.pending(subject.collection), {subject.id});

        firestore.failStatus = null;
        await subject.syncNow();

        expect(firestore.writes, 2);
        expect(subject.state(), 'synced');
      });

      test('an edit after a refusal is queued again when it fails', () async {
        firestore.failStatus = 403;
        await subject.push();
        await subject.syncNow();
        expect(firestore.writes, 1);

        firestore.failStatus = 503;
        await subject.push();
        expect(subject.state(), 'offline');
        expect(await queue.pending(subject.collection), {subject.id});

        firestore.failStatus = null;
        await subject.syncNow();

        expect(firestore.writes, 3);
        expect(subject.state(), 'synced');
      });

      test('an edit that lands clears the rejection', () async {
        firestore.failStatus = 403;
        await subject.push();
        expect(subject.state(), 'rejected');

        firestore.failStatus = null;
        await subject.push();
        await subject.syncNow();

        expect(subject.state(), 'synced');
      });

      test('a refused delete is not replayed', () async {
        firestore.failStatus = 403;
        await subject.delete!();
        expect(subject.state(), 'rejected');
        expect(await queue.pending('${subject.collection}_deleted'), isEmpty);

        await subject.syncNow();
        await subject.syncNow();

        expect(firestore.writes, 1);
        expect(subject.state(), 'rejected');
      }, skip: _withoutDelete.contains(testCase.name));
    });
  }

  test('a newer remote copy ends the rejection', () async {
    final firestore = _Firestore()..failStatus = 403;
    final entry = PitScoutEntry(
      id: 'p1',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 7, 8),
    );
    final service = DesktopPitScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      pendingPushQueue: FakePendingPushQueue(),
    );
    addTearDown(service.dispose);
    await service.push(entry);

    fc.Document remoteAt(DateTime at) => fc.Document(
      name: 'pitScoutEntries/p1',
      fields: {
        ...entry.copyWith(updatedAt: at).toJson(),
        'updatedAtTs': at,
      },
    );

    firestore.remote = [remoteAt(DateTime.utc(2026, 7, 7))];
    await service.syncNow();
    expect(service.status.state.name, 'rejected');

    firestore.remote = [remoteAt(DateTime.utc(2026, 7, 9))];
    await service.syncNow();
    expect(service.status.state.name, 'synced');
  });

  group('RejectedWrites', () {
    late FakePendingPushQueue queue;
    late RejectedWrites rejected;
    final refusal = fc.FirestoreApiException(403, 'denied');

    setUp(() {
      queue = FakePendingPushQueue();
      rejected = RejectedWrites();
    });

    test('a refusal leaves the queue and is held with its reason', () async {
      await queue.mark('docs', 'a');
      await rejected.recordFailure(
        queue,
        'docs',
        'a',
        refusal,
        at: DateTime.utc(2026),
      );

      expect(await queue.pending('docs'), isEmpty);
      expect(rejected.contains('a'), isTrue);
      expect(rejected.reason, 'denied');
    });

    test('PERMISSION_DENIED counts as a refusal, a 401 does not', () {
      expect(
        RejectedWrites.refusalReason(
          fc.FirestoreApiException(400, 'no', status: 'PERMISSION_DENIED'),
        ),
        'no',
      );
      expect(
        RejectedWrites.refusalReason(fc.FirestoreApiException(401, 'expired')),
        isNull,
      );
    });

    test('a transient failure queues the id and releases a refusal', () async {
      await rejected.recordFailure(
        queue,
        'docs',
        'a',
        refusal,
        at: DateTime.utc(2026),
      );
      await rejected.recordFailure(
        queue,
        'docs',
        'a',
        fc.FirestoreApiException(503, 'down'),
        at: DateTime.utc(2026),
      );

      expect(await queue.pending('docs'), {'a'});
      expect(rejected.isNotEmpty, isFalse);
    });

    test('only a remote copy no older than the write supersedes it', () async {
      await rejected.recordFailure(
        queue,
        'docs',
        'a',
        refusal,
        at: DateTime.utc(2026, 7, 8),
      );

      rejected.supersede('a', DateTime.utc(2026, 7, 7));
      expect(rejected.contains('a'), isTrue);

      rejected.supersede('a', DateTime.utc(2026, 7, 8));
      expect(rejected.contains('a'), isFalse);
    });
  });
}
