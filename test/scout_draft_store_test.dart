import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/services/scout_draft_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ScoutDraftStore store() =>
      ScoutDraftStore(debounce: const Duration(milliseconds: 10));

  test('round trips values and strokes for the same form', () async {
    final s = store();
    s.save(
      'form-a',
      () => const ScoutDraft(
        values: {
          'matchNumber': '12',
          'coral': 4,
          'climbed': true,
          'accuracy': 0.5,
          'team': {'teamNumber': 3847, 'robotPosition': 'R1'},
        },
        strokes: {
          'auton': [
            {'points': []},
          ],
        },
      ),
    );
    await s.flush();

    final draft = await s.load('form-a');

    expect(draft, isNotNull);
    expect(draft!.values['matchNumber'], '12');
    expect(draft.values['coral'], 4);
    expect(draft.values['climbed'], true);
    expect(draft.values['accuracy'], 0.5);
    expect(draft.values['team'], {'teamNumber': 3847, 'robotPosition': 'R1'});
    expect(draft.strokes!.keys, ['auton']);
  });

  test('discards a draft captured with a different form', () async {
    final s = store();
    s.save('form-a', () => const ScoutDraft(values: {'x': 1}));
    await s.flush();

    expect(await s.load('form-b'), isNull);
    expect(await s.load('form-a'), isNotNull);
  });

  test('clear removes the draft and a write still waiting', () async {
    final s = store();
    s.save('form-a', () => const ScoutDraft(values: {'x': 1}));
    await s.flush();
    s.save('form-a', () => const ScoutDraft(values: {'x': 2}));

    await s.clear();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await s.load('form-a'), isNull);
  });

  test('a burst of saves writes once, with the last snapshot', () async {
    final s = store();
    var snapshots = 0;
    for (var i = 0; i < 5; i++) {
      s.save('form-a', () {
        snapshots++;
        return ScoutDraft(values: {'x': i});
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(snapshots, 1);
    expect((await s.load('form-a'))!.values['x'], 4);
  });

  test(
    'a value JSON cannot hold drops the write instead of throwing',
    () async {
      final s = store();
      s.save('form-a', () => ScoutDraft(values: {'x': Object()}));

      await s.flush();

      expect(await s.load('form-a'), isNull);
    },
  );

  test('a corrupt stored draft loads as null', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ScoutDraftStore.storageKey: '{not json',
    });

    expect(await store().load('form-a'), isNull);
  });

  test('formKeyOf is stable and tells shapes apart', () {
    expect(ScoutDraftStore.formKeyOf('abc'), ScoutDraftStore.formKeyOf('abc'));
    expect(
      ScoutDraftStore.formKeyOf('abc'),
      isNot(ScoutDraftStore.formKeyOf('abd')),
    );
  });
}
