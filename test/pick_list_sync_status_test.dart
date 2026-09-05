import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/services/pick_list_storage.dart';
import 'package:spectrumstrategy/src/services/pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/ui/pick_lists_screen.dart';

import 'support/fake_pick_list_sync_service.dart';

class _InMemoryStorage implements PickListStorage {
  final Map<String, PickList> data = <String, PickList>{};
  Set<String> _synced = <String>{};

  @override
  Future<List<PickList>> loadAll() async => data.values.toList();

  @override
  Future<void> save(PickList list) async => data[list.id] = list;

  @override
  Future<void> delete(String id) async => data.remove(id);

  @override
  Future<Set<String>> loadSyncedIds() async => Set<String>.of(_synced);

  @override
  Future<void> saveSyncedIds(Set<String> ids) async =>
      _synced = Set<String>.of(ids);
}

class _FailingStorage extends _InMemoryStorage {
  bool failSaves = false;

  @override
  Future<void> save(PickList list) async {
    if (failSaves) throw StateError('disk full');
    await super.save(list);
  }
}

Future<PickListController> _pumpScreen(
  WidgetTester tester, {
  required PickListSyncState state,
  String? uid,
  PickListStorage? storage,
}) async {
  final controller = PickListController(
    storage: storage ?? _InMemoryStorage(),
    syncService: FakePickListSyncService(
      initialState: state,
      currentUserUid: uid,
    ),
    idGenerator: () => 'list-1',
    clock: () => DateTime.utc(2026, 7, 29),
  );
  await controller.bootstrap();
  await controller.create('Picks');

  await tester.pumpWidget(
    MaterialApp(home: PickListsScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('a synced list says so', (tester) async {
    await _pumpScreen(tester, state: PickListSyncState.synced, uid: 'me');

    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('an offline list says so instead of looking saved', (
    tester,
  ) async {
    await _pumpScreen(tester, state: PickListSyncState.offline, uid: 'me');

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('a signed-in user is told their own lists reach the team', (
    tester,
  ) async {
    await _pumpScreen(tester, state: PickListSyncState.synced, uid: 'me');

    expect(
      find.text('Saved and shared with your team automatically.'),
      findsOneWidget,
    );
  });

  testWidgets('a signed-out user is not promised any sharing', (tester) async {
    await _pumpScreen(tester, state: PickListSyncState.signedOut);

    expect(
      find.text('Saved on this device. Sign in to share with the team.'),
      findsOneWidget,
    );
    expect(find.text('Not signed in to sync'), findsOneWidget);
  });

  testWidgets('a write that failed to land overrides the connection state', (
    tester,
  ) async {
    final storage = _FailingStorage();
    final controller = await _pumpScreen(
      tester,
      state: PickListSyncState.synced,
      uid: 'me',
      storage: storage,
    );

    expect(find.text('Synced'), findsOneWidget);

    storage.failSaves = true;
    await controller.rename('list-1', 'Renamed');
    await tester.pumpAndSettle();

    expect(find.text('1 edit not saved'), findsOneWidget);
    expect(find.text('Synced'), findsNothing);

    storage.failSaves = false;
    await controller.rename('list-1', 'Renamed again');
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);
    expect(find.text('Synced'), findsOneWidget);
  });
}
