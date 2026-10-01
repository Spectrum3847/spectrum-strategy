import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';

void main() {
  ScoutEntry entry({
    Map<String, dynamic>? fieldValues,
    String alliance = 'Red',
  }) => ScoutEntry(
    matchId: 'm1',
    teamNumber: 254,
    alliance: alliance,
    fieldValues: fieldValues,
  );

  group('allianceFromStationValue', () {
    test('reads the six FRC stations', () {
      expect(allianceFromStationValue('R1'), 'Red');
      expect(allianceFromStationValue('R2'), 'Red');
      expect(allianceFromStationValue('R3'), 'Red');
      expect(allianceFromStationValue('B1'), 'Blue');
      expect(allianceFromStationValue('B2'), 'Blue');
      expect(allianceFromStationValue('B3'), 'Blue');
    });

    test('tolerates case and surrounding space', () {
      expect(allianceFromStationValue(' b2 '), 'Blue');
      expect(allianceFromStationValue('r3'), 'Red');
    });

    test('rejects anything that is not a station', () {
      expect(allianceFromStationValue('R4'), isNull);
      expect(allianceFromStationValue('R0'), isNull);
      expect(allianceFromStationValue('Red'), isNull);
      expect(allianceFromStationValue('R'), isNull);
      expect(allianceFromStationValue('R12'), isNull);
      expect(allianceFromStationValue('X1'), isNull);
      expect(allianceFromStationValue(''), isNull);
      expect(allianceFromStationValue(2), isNull);
      expect(allianceFromStationValue(null), isNull);
    });
  });

  group('effectiveAlliance', () {
    test('a blue station beats a stored Red', () {
      final e = entry(
        alliance: 'Red',
        fieldValues: <String, dynamic>{'robot': 'B1'},
      );
      expect(e.effectiveAlliance, 'Blue');

      expect(e.alliance, 'Red');
    });

    test('a red station agrees with a stored Red', () {
      expect(
        entry(fieldValues: <String, dynamic>{'robot': 'R2'}).effectiveAlliance,
        'Red',
      );
    });

    test('works whatever the station field is called', () {
      expect(
        entry(fieldValues: <String, dynamic>{'driverStation2027': 'B3'})
            .effectiveAlliance,
        'Blue',
      );
    });

    test('no station captured falls back to what was stored', () {
      expect(
        entry(
          alliance: 'Blue',
          fieldValues: <String, dynamic>{'scouter': 'Sam', 'autoFuel': 12},
        ).effectiveAlliance,
        'Blue',
      );
      expect(entry(alliance: 'Blue').effectiveAlliance, 'Blue');
    });

    test('two disagreeing stations fall back rather than guess', () {
      expect(
        entry(
          alliance: 'Red',
          fieldValues: <String, dynamic>{'robot': 'B1', 'defended': 'R2'},
        ).effectiveAlliance,
        'Red',
      );
    });

    test('two agreeing stations are not ambiguous', () {
      expect(
        entry(
          alliance: 'Red',
          fieldValues: <String, dynamic>{'robot': 'B1', 'partner': 'B2'},
        ).effectiveAlliance,
        'Blue',
      );
    });
  });
}
