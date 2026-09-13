import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_pit_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/services/desktop_pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_pending_push_queue.dart';
import 'support/fake_pick_list_storage.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';

class _RecordingFirestore extends fc.Firestore {
  _RecordingFirestore() : super(projectId: 'test', idTokenProvider: _token);

  static Future<String?> _token() async => 'token';

  bool failWrites = false;
  final List<String> deletedPaths = <String>[];

  @override
  Future<fc.Document> setDocument(
    String path,
    Map<String, dynamic> fields, {
    List<String>? updateMask,
  }) async {
    if (failWrites) throw fc.FirestoreApiException(503, 'unreachable');
    return fc.Document(name: path, fields: fields);
  }

  @override
  Future<void> deleteDocument(String path) async {
    if (failWrites) throw fc.FirestoreApiException(503, 'unreachable');
    deletedPaths.add(path);
  }

  @override
  Future<List<fc.Document>> listDocuments(
    String path, {
    int pageSize = 300,
  }) async => <fc.Document>[];

  @override
  Future<List<fc.Document>> runQuery(
    String collection, {
    List<fc.FieldFilter> filters = const <fc.FieldFilter>[],
    String? orderBy,
    bool descending = false,
    int? limit,
  }) async => <fc.Document>[];
}

const SpectrumUser _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

FakeSpectrumAuthService _auth() => FakeSpectrumAuthService(initialUser: _user);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingFirestore firestore;

  setUp(() => firestore = _RecordingFirestore());

  test('scout entries: a failed delete is replayed as a delete', () async {
    final storage = FakeScoutingStorage();
    final service = DesktopScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: FakePendingPushQueue(),
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.delete(ScoutEntry(id: 'e1', matchId: 'Q1', teamNumber: 3847));
    expect(firestore.deletedPaths, isEmpty);
    expect(
      service.status.pendingWrites,
      1,
      reason: 'a queued delete is an unsynced write and must be counted',
    );

    firestore.failWrites = false;
    await service.syncNow();
    expect(firestore.deletedPaths, <String>['scoutEntries/e1']);

    await service.syncNow();
    expect(
      firestore.deletedPaths,
      hasLength(1),
      reason: 'the delete leaves the queue once the server accepts it',
    );
    expect(service.status.pendingWrites, 0);
  });

  test('scout entries: a delete supersedes that entry pending push', () async {
    final storage = FakeScoutingStorage();
    final queue = FakePendingPushQueue();
    final entry = ScoutEntry(id: 'e2', matchId: 'Q2', teamNumber: 3847);
    await storage.saveEntry(entry);
    final service = DesktopScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.push(entry);
    await service.delete(entry);
    firestore.failWrites = false;

    await service.syncNow();

    expect(firestore.deletedPaths, <String>['scoutEntries/e2']);
    expect(
      await queue.pending('scoutEntries'),
      isEmpty,
      reason: 'a deleted entry has nothing left to push',
    );
  });

  test('scout entries: a push after a failed delete cancels it', () async {
    final storage = FakeScoutingStorage();
    final queue = FakePendingPushQueue();
    final entry = ScoutEntry(id: 'e3', matchId: 'Q3', teamNumber: 3847);
    await storage.saveEntry(entry);
    final service = DesktopScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: storage,
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.delete(entry);
    firestore.failWrites = false;
    await service.push(entry);

    expect(await queue.pending('scoutEntries_deleted'), isEmpty);
    await service.syncNow();
    expect(firestore.deletedPaths, isEmpty);
  });

  test('pit entries: a failed delete is replayed as a delete', () async {
    final service = DesktopPitScoutingSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: FakePitScoutingStorage(),
      pendingPushQueue: FakePendingPushQueue(),
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.delete(PitScoutEntry(id: 'p1', teamNumber: 3847));
    expect(firestore.deletedPaths, isEmpty);

    firestore.failWrites = false;
    await service.syncNow();
    expect(firestore.deletedPaths, <String>['pitScoutEntries/p1']);

    await service.syncNow();
    expect(
      firestore.deletedPaths,
      hasLength(1),
      reason: 'the delete leaves the queue once the server accepts it',
    );
  });

  test('pick lists: a failed delete is replayed as a delete', () async {
    final service = DesktopPickListSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: FakePickListStorage(),
      pendingPushQueue: FakePendingPushQueue(),
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.delete(
      PickList(
        id: 'l1',
        name: 'First pick',
        teamNumbers: const <int>[3847],
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );
    expect(firestore.deletedPaths, isEmpty);

    firestore.failWrites = false;
    await service.syncNow();
    expect(firestore.deletedPaths, <String>['pickLists/l1']);

    await service.syncNow();
    expect(
      firestore.deletedPaths,
      hasLength(1),
      reason: 'the delete leaves the queue once the server accepts it',
    );
  });

  test('pick lists: a failed delete drops that list queued team ops', () async {
    final queue = FakePendingPushQueue();
    final list = PickList(
      id: 'l2',
      name: 'Second pick',
      teamNumbers: const <int>[3847],
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final service = DesktopPickListSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: FakePickListStorage(),
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.pushTeamAdd(list, 118);
    await service.delete(list);
    expect(await queue.pending('pickLists'), isEmpty);

    firestore.failWrites = false;
    await service.syncNow();

    expect(firestore.deletedPaths, <String>['pickLists/l2']);
  });

  test('pick lists: a write after a failed delete cancels it', () async {
    final queue = FakePendingPushQueue();
    final list = PickList(
      id: 'l3',
      name: 'Third pick',
      teamNumbers: const <int>[3847],
      updatedAt: DateTime.utc(2026, 8, 1),
    );
    final service = DesktopPickListSyncService(
      authService: _auth(),
      firestore: firestore,
      storage: FakePickListStorage(),
      pendingPushQueue: queue,
    );
    addTearDown(service.dispose);

    firestore.failWrites = true;
    await service.delete(list);
    firestore.failWrites = false;
    await service.push(list);

    expect(await queue.pending('pickLists_deleted'), isEmpty);
    await service.syncNow();
    expect(firestore.deletedPaths, isEmpty);
  });
}
