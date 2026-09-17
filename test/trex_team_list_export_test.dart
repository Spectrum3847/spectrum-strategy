import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/trex_team_list.dart';
import 'package:spectrumstrategy/src/services/trex_team_list_export.dart';

void main() {
  group('TRexTeamListExport.asText', () {
    test('renders the title, each column heading, teams, and the total', () {
      final teamList = TRexTeamList(
        title: 'Pit Scouting Team Assignments',
        columns: const [
          TRexTeamListColumn(key: 'k1', name: 'Defense', teams: ['118', '254']),
          TRexTeamListColumn(key: 'k2', name: 'Auton', teams: ['1678']),
        ],
        updatedAt: DateTime.utc(2026, 8, 21),
      );

      final text = TRexTeamListExport.asText(teamList);

      expect(text, contains('Pit Scouting Team Assignments'));
      expect(text, contains('Defense'));
      expect(text, contains('118'));
      expect(text, contains('254'));
      expect(text, contains('Auton'));
      expect(text, contains('1678'));
      expect(text, contains('Total teams: 3'));

      expect(text.indexOf('Defense'), lessThan(text.indexOf('Auton')));
      expect(text.indexOf('118'), lessThan(text.indexOf('254')));
    });

    test('falls back to a default title when none was typed', () {
      final teamList = TRexTeamList(
        columns: const [TRexTeamListColumn(key: 'k1', name: 'Defense')],
        updatedAt: DateTime.utc(2026, 8, 21),
      );

      final text = TRexTeamListExport.asText(teamList);

      expect(text, startsWith('Team assignments'));
    });

    test(
      'an empty table renders a plain message rather than a blank string',
      () {
        final text = TRexTeamListExport.asText(
          TRexTeamList(
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );

        expect(text, contains('no columns added yet'));
      },
    );

    test('a column with no teams says so instead of an empty gap', () {
      final teamList = TRexTeamList(
        columns: const [TRexTeamListColumn(key: 'k1', name: 'Defense')],
        updatedAt: DateTime.utc(2026, 8, 21),
      );

      final text = TRexTeamListExport.asText(teamList);

      expect(text, contains('(no teams yet)'));
    });
  });
}
