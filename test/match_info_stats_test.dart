import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/match_info_stats.dart';
import 'package:statbotics_client/statbotics_client.dart';

ScoutEntry _entry(
  int team, {
  String match = 'qm1',
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
  String notes = '',
}) {
  return ScoutEntry(
    matchId: match,
    teamNumber: team,
    fieldValues: fieldValues,
    notes: notes,
  );
}

const _teleopFuel = ScoutConfigField(
  title: 'Teleop Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'teleopFuelScored',
);

const _autoFuel = ScoutConfigField(
  title: 'Auto Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'autoFuelScored',
);

const _autoClimb = ScoutConfigField(
  title: 'Level 1 Climb',
  type: ScoutFieldType.select,
  code: 'auLow',
  choices: <String, String>{
    'N/A': 'Not Attempted',
    'Failed': 'Failed',
    'Successful': 'Successful',
  },
);

const _highClimb = ScoutConfigField(
  title: 'High Climb (L3)',
  type: ScoutFieldType.select,
  code: 'eHigh',
  choices: <String, String>{
    'N/A': 'Not Attempted',
    'Failed': 'Failed',
    'Successful': 'Successful',
  },
);

ScoutConfig _config() {
  return const ScoutConfig(
    title: 'Scout',
    sections: [
      ScoutConfigSection(
        name: 'Auto',
        fields: [_teleopFuel, _autoFuel, _autoClimb, _highClimb],
      ),
    ],
  );
}

const _driveTrainField = ScoutConfigField(
  title: 'Drivetrain Type',
  type: ScoutFieldType.select,
  code: 'drivetrainType',
  choices: <String, String>{'swerve': 'Swerve', 'tank': 'Tank / Skid Steer'},
);

ScoutConfig _pitConfig() {
  return const ScoutConfig(
    title: 'Pit Scouting',
    sections: [
      ScoutConfigSection(name: 'Drivetrain', fields: [_driveTrainField]),
    ],
  );
}

StatboticsMatch _match({
  String key = '2026txdri1_qm1',
  int matchNumber = 1,
  required List<int> redTeams,
  required List<int> blueTeams,
}) {
  return StatboticsMatch(
    key: key,
    event: '2026txdri1',
    matchNumber: matchNumber,
    compLevel: 'qm',
    redTeams: redTeams,
    blueTeams: blueTeams,
  );
}

PitScoutEntry _pitEntry(int team, Map<String, dynamic> fieldValues) {
  return PitScoutEntry(teamNumber: team, fieldValues: fieldValues);
}

PrescoutEntry _prescoutEntry(int team, Map<String, dynamic> fieldValues) {
  return PrescoutEntry(teamNumber: team, fieldValues: fieldValues);
}

void main() {
  group('MatchInfoStats.build', () {
    test('null myTeamNumber yields no entries', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(
            redTeams: const [3847, 118, 2056],
            blueTeams: const [254, 1323, 971],
          ),
        ],
        myTeamNumber: null,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      expect(entries, isEmpty);
    });

    test('a match 3847 does not play is filtered out', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(
            key: '2026txdri1_qm2',
            matchNumber: 2,
            redTeams: const [1, 2, 3],
            blueTeams: const [4, 5, 6],
          ),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      expect(entries, isEmpty);
    });

    test(
      'on the red alliance: our full alliance in preMatch, blue in opponents',
      () {
        final entries = MatchInfoStats.build(
          matches: [
            _match(
              redTeams: const [3847, 118, 2056],
              blueTeams: const [254, 1323, 971],
            ),
          ],
          myTeamNumber: 3847,
          scoutEntries: const <ScoutEntry>[],
          config: _config(),
        );
        expect(entries, hasLength(1));
        final entry = entries.single;
        expect(entry.preMatch.map((r) => r.teamNumber), [3847, 118, 2056]);
        expect(entry.opponents.map((r) => r.teamNumber), [254, 1323, 971]);
      },
    );

    test('on the blue alliance: red is the opponents table', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(
            redTeams: const [254, 1323, 971],
            blueTeams: const [3847, 118, 2056],
          ),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      final entry = entries.single;
      expect(entry.preMatch.map((r) => r.teamNumber), [3847, 118, 2056]);
      expect(entry.opponents.map((r) => r.teamNumber), [254, 1323, 971]);
    });

    test('every match 3847 plays is included, not just the next one', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(
            key: '2026txdri1_qm1',
            matchNumber: 1,
            redTeams: const [3847, 118, 2056],
            blueTeams: const [254, 1323, 971],
          ),
          _match(
            key: '2026txdri1_qm2',
            matchNumber: 2,
            redTeams: const [1, 2, 3],
            blueTeams: const [4, 5, 6],
          ),
          _match(
            key: '2026txdri1_qm3',
            matchNumber: 3,
            redTeams: const [7, 8, 9],
            blueTeams: const [3847, 10, 11],
          ),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      expect(entries.map((e) => e.match.key), [
        '2026txdri1_qm1',
        '2026txdri1_qm3',
      ]);
    });

    test('our own row in preMatch gets stats the same way as any teammate', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(3847, match: 'qm1', fieldValues: {'teleopFuelScored': 10}),
          _entry(3847, match: 'qm2', fieldValues: {'teleopFuelScored': 30}),
        ],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 3847,
      );
      expect(row.iqmFuel.event, 20);
      expect(row.teleopAverage.event, 20);
    });

    test('row values pull from TeamSummaryStats and the plain teleop mean', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(118, match: 'qm1', fieldValues: {'teleopFuelScored': 10}),
          _entry(118, match: 'qm2', fieldValues: {'teleopFuelScored': 30}),
        ],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );

      expect(row.iqmFuel.event, 20);
      expect(row.teleopAverage.event, 20);
    });

    test(
      'teleop average differs from IQM once n reaches the quartile trim',
      () {
        final entries = MatchInfoStats.build(
          matches: [
            _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
          ],
          myTeamNumber: 3847,
          scoutEntries: [
            _entry(118, match: 'qm1', fieldValues: {'teleopFuelScored': 1}),
            _entry(118, match: 'qm2', fieldValues: {'teleopFuelScored': 2}),
            _entry(118, match: 'qm3', fieldValues: {'teleopFuelScored': 3}),
            _entry(118, match: 'qm4', fieldValues: {'teleopFuelScored': 100}),
          ],
          config: _config(),
        );
        final row = entries.single.preMatch.firstWhere(
          (r) => r.teamNumber == 118,
        );

        expect(row.iqmFuel.event, 2.5);
        expect(row.teleopAverage.event, closeTo(26.5, 1e-9));
      },
    );

    test('auto climb: any success across entries shows as the L1 flag', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(118, match: 'qm1', fieldValues: {'auLow': 'Failed'}),
          _entry(118, match: 'qm2', fieldValues: {'auLow': 'Successful'}),
          _entry(254, match: 'qm1', fieldValues: {'auLow': 'Failed'}),
        ],
        config: _config(),
      );
      final entry = entries.single;
      expect(
        entry.preMatch.firstWhere((r) => r.teamNumber == 118).autoClimb,
        isTrue,
      );
      expect(entry.opponents.first.autoClimb, isFalse);
    });

    test('team name and robot type are joined in from the supplied maps', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
        pitConfig: _pitConfig(),
        teamNames: const {118: 'Robonauts'},
        pitEntryByTeam: {
          118: _pitEntry(118, const {
            'drivetrainType': 'swerve',
            'trenchFit': true,
            'launcherType': 'Flywheel',
          }),
        },
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.teamName, 'Robonauts');

      expect(row.robotType, 'Swerve · trench · Flywheel');
    });

    test('a team present on both alliances of a malformed match is not its '
        'own opponent', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(
            redTeams: const [3847, 118, 2056],
            blueTeams: const [3847, 1323, 971],
          ),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      final entry = entries.single;
      expect(entry.preMatch.map((r) => r.teamNumber), [3847, 118, 2056]);
      expect(entry.opponents.map((r) => r.teamNumber), isNot(contains(3847)));
    });

    test('a team with no scouting or pit data still gets a row, all blank', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.teamName, isNull);
      expect(row.robotType, '');
      expect(row.iqmFuel.isEmpty, isTrue);
      expect(row.teleopAverage.isEmpty, isTrue);
      expect(row.autoClimb, isFalse);
    });
  });

  group('MatchInfoStats.rowsFor', () {
    test(
      'is alliance-format-agnostic: a plain team list in, rows out in order',
      () {
        final rows = MatchInfoStats.rowsFor(
          const [4, 5, 6],
          summaryByTeam: const {},
          entriesByTeam: const {},
          teleopField: null,
          teamNames: const {5: 'Middle Pick'},
        );
        expect(rows.map((r) => r.teamNumber), [4, 5, 6]);
        expect(rows[1].teamName, 'Middle Pick');
      },
    );
  });

  group('source-labelled stats (#1843)', () {
    test('event value only: no source label needed', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(118, fieldValues: {'autoFuelScored': 40}),
        ],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.maxAuto.event, 40);
      expect(row.maxAuto.prescout, isNull);
    });

    test('prescout value only: shown labelled as prescout', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
        prescoutEntries: [
          _prescoutEntry(118, const {'autoFuelScored': 60}),
        ],
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.maxAuto.event, isNull);
      expect(row.maxAuto.prescout, 60);
    });

    test('both event and prescout data present: both carried on the row', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(118, fieldValues: {'autoFuelScored': 40}),
        ],
        config: _config(),
        prescoutEntries: [
          _prescoutEntry(118, const {'autoFuelScored': 60}),
        ],
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.maxAuto.event, 40);
      expect(row.maxAuto.prescout, 60);
    });
  });

  group('drive coach, endgame climb, and notes (#1843)', () {
    test('drive coach comes from the pit form', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
        pitEntryByTeam: {
          118: _pitEntry(118, const {'driveCoachName': 'Alex'}),
        },
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.driveCoach, 'Alex');
    });

    test('endgame climb reports the highest level any source recorded', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(118, fieldValues: {'eHigh': 'Successful'}),
        ],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.endgameClimb, 'L3');
    });

    test('endgame climb is blank when nobody recorded a success', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [
          _entry(118, fieldValues: {'eHigh': 'Failed'}),
        ],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.endgameClimb, '');
    });

    test('notes combine scout comments and pit comments', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: [_entry(118, notes: 'played great defense')],
        config: _config(),
        pitEntryByTeam: {
          118: _pitEntry(118, const {'comments': 'swerve, fast robot'}),
        },
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.notes, contains('played great defense'));
      expect(row.notes, contains('swerve, fast robot'));
    });

    test('notes are blank with nothing written anywhere', () {
      final entries = MatchInfoStats.build(
        matches: [
          _match(redTeams: const [3847, 118], blueTeams: const [254, 1323]),
        ],
        myTeamNumber: 3847,
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );
      final row = entries.single.preMatch.firstWhere(
        (r) => r.teamNumber == 118,
      );
      expect(row.notes, '');
    });
  });
}
