import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_config_service.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('loadDefault parses the bundled default scout config asset', () async {
    final config = await ScoutConfigService().loadDefault();
    expect(config.sections, isNotEmpty);

    final codes = <String>{
      for (final section in config.sections)
        for (final field in section.fields) field.code,
    };
    expect(codes, contains('pTnumber'));
    expect(codes, contains('matchNumber'));
  });

  test(
    'the default match field picks from the schedule, not free text',
    () async {
      final config = await ScoutConfigService().loadDefault();
      final match = config.allFields.firstWhere((f) => f.code == 'matchNumber');

      expect(match.type, ScoutFieldType.tbaMatchNumber);
    },
  );

  test('seedConfig is a valid minimal placeholder', () {
    final seed = ScoutConfigService.seedConfig;
    expect(seed.sections, isEmpty);
  });

  test(
    'the default form carries auto fuel, auto L1 climb, and comments',
    () async {
      final config = await ScoutConfigService().loadDefault();
      final codes = <String>{for (final f in config.allFields) f.code};
      expect(
        codes,
        containsAll(<String>['autoFuelScored', 'auLow', 'comments']),
      );
    },
  );

  test(
    'the question order matches the database column order (#1381)',
    () async {
      final config = await ScoutConfigService().loadDefault();
      final codes = config.allFields.map((f) => f.code).toList(growable: false);
      expect(codes, <String>[
        'scouter',
        'matchNumber',
        'robot',
        'pTnumber',
        'starting',
        'autoFuelScored',
        'auLow',
        'teleopFuelScored',
        'scoringEff',
        'tRdefense',
        'tRpasser',
        'ePclimb',
        'eLow',
        'eMiddle',
        'eHigh',
        'ryCard',
        'dieCard',
        'comments',
      ]);
    },
  );

  test('scoring accuracy is a 0-100 slider stepping by 5 (#1381)', () async {
    final config = await ScoutConfigService().loadDefault();
    final accuracy = config.allFields.firstWhere((f) => f.code == 'scoringEff');
    expect(accuracy.type, ScoutFieldType.range);
    expect(accuracy.min, 0);
    expect(accuracy.max, 100);
    expect(accuracy.step, 5);
  });

  test(
    'climb position stays Not attempted/Outpost/Middle/Depot (#1381)',
    () async {
      final config = await ScoutConfigService().loadDefault();
      final climbPosition = config.allFields.firstWhere(
        (f) => f.code == 'ePclimb',
      );
      expect(climbPosition.retiredChoiceKeys, isEmpty);
      expect(climbPosition.activeChoices.keys, <String>[
        'N/A',
        'Outpost',
        'Middle',
        'Depot',
      ]);
    },
  );

  test('the climb level fields are position dropdowns, retiring Failed/Successful (#1381)', () async {
    final config = await ScoutConfigService().loadDefault();
    for (final code in <String>['eLow', 'eMiddle', 'eHigh']) {
      final field = config.allFields.firstWhere((f) => f.code == code);
      expect(field.retiredChoiceKeys, <String>{'Failed', 'Successful'});
      expect(field.activeChoices.keys, <String>[
        'N/A',
        'Outpost',
        'Middle',
        'Depot',
      ]);
      expect(field.choices, containsPair('Failed', 'Failed'));
      expect(field.choices, containsPair('Successful', 'Successful'));
    }
  });
}
