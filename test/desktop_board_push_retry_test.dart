import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/desktop_strategy_board_sync_service.dart';
import 'package:spectrumstrategy/src/services/pending_push_queue.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_spectrum_auth_service.dart';

class _RecordingFirestore extends fc.Firestore {
  _RecordingFirestore() : super(projectId: 'test', idTokenProvider: _token);

  static Future<String?> _token() async => 'token';

  bool failWrites = false;
  final List<String> setPaths = <String>[];
  final List<String> deletedPaths = <String>[];

  @override
  Future<fc.Document> setDocument(
    String path,
    Map<String, dynamic> fields, {
    List<String>? updateMask,
  }) async {
    if (failWrites) throw fc.FirestoreApiException(503, 'unreachable');
    setPaths.add(path);
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
    String path, {
    List<fc.FieldFilter> filters = const [],
    String? orderBy,
    bool descending = false,
    int? limit,
  }) async => <fc.Document>[];
}

const SpectrumUser _user = SpectrumUser(uid: 'uid-1', displayName: 'Tester');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingFirestore firestore;
  late FakeMatchDirectory directory;
  late DesktopStrategyBoardSyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    firestore = _RecordingFirestore();
    directory = FakeMatchDirectory();
    service = DesktopStrategyBoardSyncService(
      authService: FakeSpectrumAuthService(initialUser: _user),
      firestore: firestore,
      directory: directory,
      pendingPushQueue: PendingPushQueue(),
    );
    addTearDown(service.dispose);
  });

  test('a failed push is replayed on the next sync', () async {
    final board = StrategySession.create(id: 'board-1');
    await directory.saveMatch(board);

    firestore.failWrites = true;
    await service.push(board);
    expect(firestore.setPaths, isEmpty);

    firestore.failWrites = false;
    await service.syncNow();

    expect(firestore.setPaths, <String>['strategyBoards/board-1']);
  });

  test('the replay stops once it lands', () async {
    final board = StrategySession.create(id: 'board-1');
    await directory.saveMatch(board);
    firestore.failWrites = true;
    await service.push(board);
    firestore.failWrites = false;

    await service.syncNow();
    await service.syncNow();

    expect(firestore.setPaths, <String>[
      'strategyBoards/board-1',
    ], reason: 'a second poll must not push a board that already landed');
  });

  test('the replay reads the board as it is now, not as it failed', () async {
    final board = StrategySession.create(id: 'board-1');
    board.matchNumber = 4;
    await directory.saveMatch(board);
    firestore.failWrites = true;
    await service.push(board);

    board.matchNumber = 9;
    await directory.saveMatch(board);
    firestore.failWrites = false;
    await service.syncNow();

    expect(firestore.setPaths, hasLength(1));
    final stored = await directory.loadMatch('board-1');
    expect(stored!.matchNumber, 9);
  });

  test('a board deleted locally before the retry is dropped', () async {
    final board = StrategySession.create(id: 'board-1');
    await directory.saveMatch(board);
    firestore.failWrites = true;
    await service.push(board);
    await directory.deleteMatch('board-1');

    firestore.failWrites = false;
    await service.syncNow();

    expect(firestore.setPaths, isEmpty);
  });

  test('a failed delete is replayed as a delete', () async {
    firestore.failWrites = true;
    await service.delete(StrategySession.create(id: 'board-2'));
    expect(firestore.deletedPaths, isEmpty);

    firestore.failWrites = false;
    await service.syncNow();

    expect(firestore.deletedPaths, <String>['strategyBoards/board-2']);

    await service.syncNow();
    expect(
      firestore.deletedPaths,
      hasLength(1),
      reason: 'the delete leaves the queue once the server accepts it',
    );
  });
}
