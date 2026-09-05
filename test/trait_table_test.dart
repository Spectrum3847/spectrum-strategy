import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trait_config.dart';
import 'package:spectrumstrategy/src/models/trait_table.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 12);

  TraitTable table({Map<int, Map<String, String>>? cells}) => TraitTable(
    id: TraitTable.idFor('2026miket', 'qm14'),
    eventKey: '2026miket',
    matchId: 'qm14',
    cells: cells,
    authorUid: 'uid-1',
    authorDisplayName: 'Lead',
    updatedAt: now,
  );

  group('identity', () {
    test('the id is derived from the event and match, not random', () {
      expect(TraitTable.idFor('2026miket', 'qm14'), '2026miket_qm14');
      expect(
        TraitTable.idFor('2026miket', 'qm14'),
        TraitTable.idFor('2026miket', 'qm14'),
      );
    });

    test('different matches at one event do not collide', () {
      expect(
        TraitTable.idFor('2026miket', 'qm14'),
        isNot(TraitTable.idFor('2026miket', 'qm15')),
      );
    });
  });

  group('editing a cell', () {
    test('sets a value and leaves the rest alone', () {
      final before = table(
        cells: {
          254: {'defense': 'strong'},
        },
      );
      final after = before.withCell(
        teamNumber: 254,
        traitKey: 'teleopScoring',
        value: 'about 55',
        updatedAt: now,
      );

      expect(after.valueFor(254, 'teleopScoring'), 'about 55');
      expect(after.valueFor(254, 'defense'), 'strong');
    });

    test('does not mutate the table it was called on', () {
      final before = table();
      before.withCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'strong',
        updatedAt: now,
      );

      expect(before.valueFor(254, 'defense'), isEmpty);
    });

    test('clearing a value removes the cell rather than storing an empty', () {
      final after =
          table(
            cells: {
              254: {'defense': 'strong', 'endgame': 'deep climb'},
            },
          ).withCell(
            teamNumber: 254,
            traitKey: 'defense',
            value: '',
            updatedAt: now,
          );

      expect(after.cells[254]!.containsKey('defense'), isFalse);
      expect(after.valueFor(254, 'endgame'), 'deep climb');
    });

    test('a team left with nothing drops out entirely', () {
      final after =
          table(
            cells: {
              254: {'defense': 'strong'},
            },
          ).withCell(
            teamNumber: 254,
            traitKey: 'defense',
            value: '   ',
            updatedAt: now,
          );

      expect(after.cells.containsKey(254), isFalse);
      expect(after.isEmpty, isTrue);
    });

    test('records who wrote it', () {
      final after = table().withCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'strong',
        updatedAt: now,
        authorUid: 'uid-2',
        authorDisplayName: 'Other Lead',
      );

      expect(after.authorUid, 'uid-2');
      expect(after.authorDisplayName, 'Other Lead');
    });
  });

  group('round trip', () {
    test('survives toJson then fromJson unchanged', () {
      final before = table(
        cells: {
          254: {'teleopScoring': 'about 55', 'defense': 'strong'},
          118: {'endgame': 'deep climb'},
        },
      );
      final after = TraitTable.fromJson(before.toJson());

      expect(after.id, before.id);
      expect(after.eventKey, before.eventKey);
      expect(after.matchId, before.matchId);
      expect(after.authorUid, before.authorUid);
      expect(after.updatedAt, before.updatedAt);
      expect(after.valueFor(254, 'teleopScoring'), 'about 55');
      expect(after.valueFor(118, 'endgame'), 'deep climb');
      expect(after.teamNumbers, [118, 254]);
    });

    test(
      'team numbers come back as ints, not as the strings Firestore holds',
      () {
        final json = table(
          cells: {
            254: {'defense': 'strong'},
          },
        ).toJson();

        expect((json['cells'] as Map).keys.single, '254');
        expect(TraitTable.fromJson(json).cells.keys.single, 254);
      },
    );

    test('a key that is not a team number is dropped, not carried forward', () {
      final after = TraitTable.fromJson({
        'id': '2026miket_qm14',
        'eventKey': '2026miket',
        'matchId': 'qm14',
        'cells': {
          '254': {'defense': 'strong'},
          'notATeam': {'defense': 'nonsense'},
        },
        'updatedAt': now.toIso8601String(),
      });

      expect(after.cells.keys.toList(), [254]);
    });

    test('a document with no updatedAt reads as the epoch, not as now', () {
      final after = TraitTable.fromJson(const {
        'id': 'x',
        'eventKey': 'e',
        'matchId': 'm',
      });

      expect(after.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('an id is rebuilt from the event and match when absent', () {
      final after = TraitTable.fromJson(const {
        'eventKey': '2026miket',
        'matchId': 'qm14',
      });

      expect(after.id, '2026miket_qm14');
    });
  });

  group('trait config', () {
    test('a missing document falls back to the defaults', () {
      expect(TraitConfig.fromJson(null).traits, isNotEmpty);
      expect(TraitConfig.fromJson(const {}).traits, isNotEmpty);
      expect(
        TraitConfig.fromJson(const {'traits': []}).traits,
        TraitConfig.defaults.traits,
      );
    });

    test('every default row has a unique key', () {
      final keys = TraitConfig.defaults.traits.map((t) => t.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('a duplicate key is dropped, so two rows cannot share a cell', () {
      final config = TraitConfig.fromJson(const {
        'traits': [
          {'key': 'defense', 'label': 'Defense'},
          {'key': 'defense', 'label': 'Defence'},
          {'key': 'endgame', 'label': 'Endgame'},
        ],
      });

      expect(config.traits.map((t) => t.key), ['defense', 'endgame']);
      expect(config.byKey('defense')!.label, 'Defense');
    });

    test('a row with no key or no label is dropped', () {
      final config = TraitConfig.fromJson(const {
        'traits': [
          {'key': 'defense', 'label': 'Defense'},
          {'key': '', 'label': 'Nameless'},
          {'label': 'No key'},
          {'key': 'nolabel'},
          'not a map',
        ],
      });

      expect(config.traits.map((t) => t.key), ['defense']);
    });

    test('an unknown source reads as no prefill rather than throwing', () {
      final config = TraitConfig.fromJson(const {
        'traits': [
          {'key': 'x', 'label': 'X', 'source': 'somethingElse'},
        ],
      });

      expect(config.traits.single.source, TraitSource.none);
    });

    test('config round trips', () {
      final after = TraitConfig.fromJson(TraitConfig.defaults.toJson());

      expect(
        after.traits.map((t) => t.key),
        TraitConfig.defaults.traits.map((t) => t.key),
      );
      expect(after.byKey('teleopScoring')!.source, TraitSource.phaseScore);
      expect(after.byKey('teleopScoring')!.phase, 'teleop');
    });
  });
}
