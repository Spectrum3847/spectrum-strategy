import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_team_list.dart';

void main() {
  group('TRexTeamList', () {
    test('round-trips through toJson/fromJson', () {
      final teamList = TRexTeamList(
        title: 'Pit Scouting Team Assignments',
        columns: const [
          TRexTeamListColumn(key: 'k1', name: 'Defense', teams: ['118', '254']),
          TRexTeamListColumn(key: 'k2', name: 'Auton', teams: ['1678']),
        ],
        authorUid: 'uid-1',
        authorDisplayName: 'Lead',
        updatedAt: DateTime.utc(2026, 8, 21),
      );

      final decoded = TRexTeamList.fromJson(teamList.toJson());

      expect(decoded.title, 'Pit Scouting Team Assignments');
      expect(decoded.columns.map((c) => c.key), ['k1', 'k2']);
      expect(decoded.columns.first.name, 'Defense');
      expect(decoded.columns.first.teams, ['118', '254']);
      expect(decoded.authorUid, 'uid-1');
      expect(decoded.authorDisplayName, 'Lead');
      expect(decoded.updatedAt, DateTime.utc(2026, 8, 21));
    });

    test('a missing document decodes as empty, not a crash', () {
      final decoded = TRexTeamList.fromJson(null);

      expect(decoded.isEmpty, isTrue);
      expect(decoded.columns, isEmpty);
      expect(decoded.title, isEmpty);
    });

    test('drops a column with no key or no name', () {
      final decoded = TRexTeamList.fromJson({
        'columns': [
          {'key': 'k1', 'name': 'Defense', 'teams': <String>[]},
          {'name': 'No key'},
          {'key': 'k2'},
          'not a map',
        ],
      });

      expect(decoded.columns.map((c) => c.key), ['k1']);
    });

    test('drops a blank team from the teams list', () {
      final decoded = TRexTeamList.fromJson({
        'columns': [
          {
            'key': 'k1',
            'name': 'Defense',
            'teams': ['118', '', '   ', 254],
          },
        ],
      });

      expect(decoded.columns.single.teams, ['118']);
    });

    test('byKey finds the matching column', () {
      final teamList = TRexTeamList(
        columns: const [TRexTeamListColumn(key: 'k1', name: 'Defense')],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      expect(teamList.byKey('k1')?.name, 'Defense');
      expect(teamList.byKey('missing'), isNull);
    });

    test('totalTeams sums every entry across every column', () {
      final teamList = TRexTeamList(
        columns: const [
          TRexTeamListColumn(key: 'k1', name: 'Defense', teams: ['118', '254']),
          TRexTeamListColumn(key: 'k2', name: 'Auton', teams: ['1678']),
          TRexTeamListColumn(key: 'k3', name: 'Empty'),
        ],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      expect(teamList.totalTeams, 3);
    });

    test('totalTeams counts a repeated team once per column', () {
      final teamList = TRexTeamList(
        columns: const [
          TRexTeamListColumn(key: 'k1', name: 'Defense', teams: ['118']),
          TRexTeamListColumn(key: 'k2', name: 'Auton', teams: ['118']),
        ],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      expect(teamList.totalTeams, 2);
    });
  });
}
