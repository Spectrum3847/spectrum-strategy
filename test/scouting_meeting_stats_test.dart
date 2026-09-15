import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_meeting_stats.dart';

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
const _ryCard = ScoutConfigField(
  title: 'Yellow/Red Card',
  type: ScoutFieldType.boolean,
  code: 'ryCard',
);

ScoutConfig _config() {
  return const ScoutConfig(
    title: 'Scout',
    sections: [
      ScoutConfigSection(name: 'Auto', fields: [_autoFuel]),
      ScoutConfigSection(name: 'Teleop', fields: [_teleopFuel]),
      ScoutConfigSection(name: 'Post match', fields: [_ryCard]),
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

void main() {
  group('ScoutingMeetingStats.rankedTeams', () {
    test('ranks teams best to worst by IQM total score', () {
      final entries = [
        _entry(1, fieldValues: {'autoFuelScored': 2, 'teleopFuelScored': 10}),
        _entry(2, fieldValues: {'autoFuelScored': 5, 'teleopFuelScored': 20}),
      ];

      final rows = ScoutingMeetingStats.rankedTeams(
        scoutEntries: entries,
        config: _config(),
        teamNames: const {2: 'Kicks'},
      );

      expect(rows.map((r) => r.teamNumber), [2, 1]);
      expect(rows.first.teamName, 'Kicks');
      expect(rows.first.iqmTeleop, isNotNull);
    });

    test('empty when there are no scout entries', () {
      expect(ScoutingMeetingStats.rankedTeams(scoutEntries: const []), isEmpty);
    });
  });

  group('ScoutingMeetingStats.tankDrivetrainTeams', () {
    test('matches the resolved drivetrain label, not the raw stored value', () {
      final pitEntryByTeam = {
        111: PitScoutEntry(
          teamNumber: 111,
          fieldValues: {'drivetrainType': 'tank'},
        ),
        222: PitScoutEntry(
          teamNumber: 222,
          fieldValues: {'drivetrainType': 'swerve'},
        ),
      };

      final teams = ScoutingMeetingStats.tankDrivetrainTeams(
        pitEntryByTeam: pitEntryByTeam,
        pitConfig: _pitConfig(),
      );

      expect(teams, [111]);
    });

    test('empty with no pit entries', () {
      expect(
        ScoutingMeetingStats.tankDrivetrainTeams(pitEntryByTeam: const {}),
        isEmpty,
      );
    });
  });

  group('ScoutingMeetingStats.cardedTeams', () {
    test('collects distinct teams with a true ryCard entry', () {
      final entries = [
        _entry(1, match: 'qm1', fieldValues: {'ryCard': true}),
        _entry(1, match: 'qm5', fieldValues: {'ryCard': false}),
        _entry(2, match: 'qm2', fieldValues: {'ryCard': 'true'}),
        _entry(3, match: 'qm3', fieldValues: {}),
      ];

      expect(ScoutingMeetingStats.cardedTeams(entries), [1, 2]);
    });

    test('empty when nobody is carded', () {
      expect(ScoutingMeetingStats.cardedTeams(const []), isEmpty);
    });
  });
}
