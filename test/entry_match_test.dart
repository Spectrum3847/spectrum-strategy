import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/entry_match.dart';

ScoutEntry entry({
  String matchId = '',
  String? tbaMatchKey,
  Object? typedMatchNumber,
}) => ScoutEntry(
  matchId: matchId,
  teamNumber: 3847,
  tbaMatchKey: tbaMatchKey,
  fieldValues: typedMatchNumber == null
      ? <String, dynamic>{}
      : <String, dynamic>{'matchNumber': typedMatchNumber},
);

void main() {
  group('parseMatchLabel', () {
    test('reads the forms a scouter writes', () {
      expect(parseMatchLabel('12'), (level: null, number: 12));
      expect(parseMatchLabel('Q12'), (level: 'qm', number: 12));
      expect(parseMatchLabel('qm12'), (level: 'qm', number: 12));
      expect(parseMatchLabel('Match 12'), (level: 'qm', number: 12));
      expect(parseMatchLabel('sf3'), (level: 'sf', number: 3));
    });

    test('reads a TBA key past its event key', () {
      expect(parseMatchLabel('2026txhou_qm12'), (level: 'qm', number: 12));

      expect(parseMatchLabel('2026txdri_f1m2'), (level: 'f', number: 2));
    });

    test('a session uuid names no match', () {
      expect(parseMatchLabel('a1b2c3d4-e5f6-4789-8abc-def012345678'), isNull);
      expect(parseMatchLabel('practice'), isNull);
      expect(parseMatchLabel(''), isNull);
    });
  });

  group('matchNumberOfEntry', () {
    test('prefers the TBA key over what was typed', () {
      final e = entry(tbaMatchKey: '2026txhou_qm14', typedMatchNumber: '13');
      expect(matchNumberOfEntry(e), 14);
    });

    test('falls back to the typed field, leniently', () {
      expect(matchNumberOfEntry(entry(typedMatchNumber: 'Q12')), 12);
      expect(matchNumberOfEntry(entry(typedMatchNumber: 12)), 12);
      expect(matchNumberOfEntry(entry(typedMatchNumber: ' 12 ')), 12);
    });

    test('ignores a session uuid in matchId', () {
      expect(
        matchNumberOfEntry(
          entry(matchId: 'a1b2c3d4-e5f6-4789-8abc-def012345678'),
        ),
        isNull,
      );
    });

    test('still reads a matchId that is a real match id', () {
      expect(matchNumberOfEntry(entry(matchId: 'qm7')), 7);
    });
  });

  group('matchGroupKeyOfEntry', () {
    test('joins entries saved from different sources', () {
      final fromForm = entry(
        matchId: 'a1b2c3d4-e5f6-4789-8abc-def012345678',
        tbaMatchKey: '2026txhou_qm14',
      );
      final fromQr = entry(typedMatchNumber: 'qm14');

      expect(matchNumberOfEntry(fromForm), matchNumberOfEntry(fromQr));
    });

    test('unplaceable entries keep their own id rather than one pile', () {
      expect(matchGroupKeyOfEntry(entry(matchId: 'board-a')), 'board-a');
      expect(matchGroupKeyOfEntry(entry(matchId: 'board-b')), 'board-b');
    });
  });

  group('matchLabelOfEntry', () {
    test('names the level the way the schedule does', () {
      expect(matchLabelOfEntry(entry(typedMatchNumber: 'qm12')), 'Match 12');
      expect(matchLabelOfEntry(entry(typedMatchNumber: 'sf3')), 'Semifinal 3');
      expect(matchLabelOfEntry(entry(typedMatchNumber: '12')), 'Match 12');
    });

    test('an entry naming no match says so instead of inventing one', () {
      expect(matchLabelOfEntry(entry()), 'No match');
    });
  });
}
