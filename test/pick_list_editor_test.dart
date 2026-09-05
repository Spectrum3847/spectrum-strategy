import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/services/pick_list_storage.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/ui/pick_lists_screen.dart';

import 'support/fake_pick_list_sync_service.dart';

class _InMemoryStorage implements PickListStorage {
  final Map<String, PickList> data = <String, PickList>{};

  @override
  Future<List<PickList>> loadAll() async => data.values.toList();

  @override
  Future<void> save(PickList list) async => data[list.id] = list;

  @override
  Future<void> delete(String id) async => data.remove(id);

  Set<String> _synced = <String>{};

  @override
  Future<Set<String>> loadSyncedIds() async => Set<String>.of(_synced);

  @override
  Future<void> saveSyncedIds(Set<String> ids) async =>
      _synced = Set<String>.of(ids);
}

void main() {
  testWidgets('a comma/space separated list adds every team in one go', (
    tester,
  ) async {
    final controller = PickListController(
      storage: _InMemoryStorage(),
      syncService: FakePickListSyncService(),
      idGenerator: () => 'list-1',
      clock: () => DateTime.utc(2026, 6, 27),
    );
    await controller.bootstrap();
    final list = (await controller.create('Picks'))!;

    await tester.pumpWidget(
      MaterialApp(
        home: PickListEditorScreen(controller: controller, listId: list.id),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '3847, 254 118');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.byId(list.id)!.teamNumbers, <int>[3847, 254, 118]);

    expect(find.text('3847, 254 118'), findsNothing);
    expect(
      (tester.widget<TextField>(find.byType(TextField))).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('junk and duplicates are ignored', (tester) async {
    final controller = PickListController(
      storage: _InMemoryStorage(),
      syncService: FakePickListSyncService(),
      idGenerator: () => 'list-1',
      clock: () => DateTime.utc(2026, 6, 27),
    );
    await controller.bootstrap();
    final list = (await controller.create('Picks'))!;
    await controller.addTeam(list.id, 3847);

    await tester.pumpWidget(
      MaterialApp(
        home: PickListEditorScreen(controller: controller, listId: list.id),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'abc, 3847, 254');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.byId(list.id)!.teamNumbers, <int>[3847, 254]);
  });
}
