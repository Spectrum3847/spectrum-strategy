import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/robot_type.dart';

PitScoutEntry _entry(Map<String, dynamic> fieldValues) {
  return PitScoutEntry(teamNumber: 3847, fieldValues: fieldValues);
}

const _driveTrainField = ScoutConfigField(
  title: 'Drivetrain Type',
  type: ScoutFieldType.select,
  code: 'drivetrainType',
  choices: <String, String>{
    'tank': 'Tank / Skid Steer',
    'swerve': 'Swerve',
    'mecanum': 'Mecanum',
    'omni': 'Omni',
    'other': 'Other',
  },
);

void main() {
  group('RobotType.composeFrom', () {
    test('no pit entry: empty, never a crash', () {
      expect(RobotType.composeFrom(null), '');
    });

    test('no fields answered: empty', () {
      expect(
        RobotType.composeFrom(
          _entry(const {}),
          driveTrainField: _driveTrainField,
        ),
        '',
      );
    });

    test('a stored choice key resolves to its display label', () {
      final type = RobotType.composeFrom(
        _entry(const {
          'drivetrainType': 'swerve',
          'trenchFit': true,
          'launcherType': 'Flywheel',
        }),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'Swerve · trench · Flywheel');
    });

    test('a stored legacy label (pre choice-key migration) still resolves', () {
      final type = RobotType.composeFrom(
        _entry(const {
          'drivetrainType': 'Swerve',
          'trenchFit': true,
          'launcherType': 'Flywheel',
        }),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'Swerve · trench · Flywheel');
    });

    test('trench false maps to "bump"', () {
      final type = RobotType.composeFrom(
        _entry(const {
          'drivetrainType': 'tank',
          'trenchFit': false,
          'launcherType': 'Catapult',
        }),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'Tank / Skid Steer · bump · Catapult');
    });

    test('missing drive train value drops that part, not a blank slot', () {
      final type = RobotType.composeFrom(
        _entry(const {'trenchFit': true, 'launcherType': 'Flywheel'}),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'trench · Flywheel');
    });

    test('no field definition supplied falls back to the raw stored value', () {
      final type = RobotType.composeFrom(
        _entry(const {'drivetrainType': 'swerve', 'trenchFit': true}),
      );
      expect(type, 'swerve · trench');
    });

    test('missing trench answer drops that part entirely', () {
      final type = RobotType.composeFrom(
        _entry(const {'drivetrainType': 'swerve', 'launcherType': 'Flywheel'}),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'Swerve · Flywheel');
    });

    test('missing launcher type drops that part', () {
      final type = RobotType.composeFrom(
        _entry(const {'drivetrainType': 'swerve', 'trenchFit': true}),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'Swerve · trench');
    });

    test('blank string fields are treated as unanswered', () {
      final type = RobotType.composeFrom(
        _entry(const {
          'drivetrainType': '',
          'trenchFit': true,
          'launcherType': '  ',
        }),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'trench');
    });

    test('a stringly-typed boolean still resolves', () {
      final type = RobotType.composeFrom(
        _entry(const {'drivetrainType': 'swerve', 'trenchFit': 'true'}),
        driveTrainField: _driveTrainField,
      );
      expect(type, 'Swerve · trench');
    });
  });
}
