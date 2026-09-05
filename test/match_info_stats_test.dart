import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/match_info_stats.dart';
import 'package:statbotics_client/statbotics_client.dart';

ScoutEntry _entry(
  int team, {
  String match = 'qm1',
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
}) {
  return ScoutEntry(matchId: match, teamNumber: team, fieldValues: fieldValues);
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

ScoutConfig _config() {
  return const ScoutConfig(
    title: 'Scout',
    sections: [
      ScoutConfigSection(
        name: 'Auto',
        fields: [_teleopFuel, _autoFuel, _autoClimb],
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
      'on the red alliance: teammates minus us in preMatch, blue in opponents',
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
        expect(entry.preMatch.map((r) => r.teamNumber), [118, 2056]);
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
      expect(entry.preMatch.map((r) => r.teamNumber), [118, 2056]);
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
      final row = entries.single.preMatch.single;
      expect(row.teamNumber, 118);

      expect(row.iqmFuel, 20);
      expect(row.teleopAverage, 20);
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
        final row = entries.single.preMatch.single;

        expect(row.iqmFuel, 2.5);
        expect(row.teleopAverage, closeTo(26.5, 1e-9));
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
      expect(entry.preMatch.single.everClimbedAutoL1, isTrue);
      expect(entry.opponents.first.everClimbedAutoL1, isFalse);
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
      final row = entries.single.preMatch.single;
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
      expect(entry.preMatch.map((r) => r.teamNumber), isNot(contains(3847)));
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
      final row = entries.single.preMatch.single;
      expect(row.teamNumber, 118);
      expect(row.teamName, isNull);
      expect(row.robotType, '');
      expect(row.iqmFuel, isNull);
      expect(row.teleopAverage, isNull);
      expect(row.everClimbedAutoL1, isFalse);
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
}
