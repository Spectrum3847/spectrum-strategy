import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/team_filters.dart';

const _event = '2026test';

ScoutConfigField _climb(String code) => ScoutConfigField(
  title: 'Climb',
  type: ScoutFieldType.select,
  code: code,
  choices: const <String, String>{
    'N/A': 'Not Attempted',
    'Failed': 'Failed',
    'Successful': 'Successful',
    'Outpost': 'Outpost',
  },
  retiredChoiceKeys: const {'Outpost'},
);

final _config = ScoutConfig(
  title: 'Scout',
  sections: [
    ScoutConfigSection(name: 'Auto', fields: [_climb('auLow')]),
    const ScoutConfigSection(
      name: 'Teleop',
      fields: [
        ScoutConfigField(
          title: 'Fuel',
          type: ScoutFieldType.counter,
          code: 'teleopFuelScored',
        ),
      ],
    ),
    ScoutConfigSection(name: 'Endgame', fields: [_climb('eHigh')]),
  ],
);

var _matchCounter = 0;

ScoutEntry _entry(int team, Map<String, dynamic> values, {String? key}) {
  _matchCounter++;
  return ScoutEntry(
    matchId: '',
    teamNumber: team,
    tbaMatchKey: key ?? '${_event}_qm$_matchCounter',
    fieldValues: values,
  );
}

PitScoutEntry _pit(int team, [Map<String, dynamic>? values]) =>
    PitScoutEntry(teamNumber: team, fieldValues: values ?? const {});

Set<int> _passing(
  TeamFilter filter, {
  List<ScoutEntry> entries = const [],
  Map<int, PitScoutEntry> pit = const {},
  List<int> teams = const [1, 2],
  String eventKey = _event,
}) {
  final results = TeamFilters.evaluate(
    teams: teams,
    entries: entries,
    pitByTeam: pit,
    eventKey: eventKey,
    config: _config,
  );
  return {
    for (final team in teams)
      if (results.passes(team, {filter})) team,
  };
}

List<ScoutEntry> _roleEntries(int team, String code, int yes, int total) => [
  for (var i = 0; i < total; i++) _entry(team, {code: i < yes}),
];

void main() {
  group('trenchFit', () {
    test('passes only on a latest pit entry that says it fits', () {
      final pit = {
        1: _pit(1, {'trenchFit': true}),
        2: _pit(2, {'trenchFit': false}),
        3: _pit(3),
      };
      expect(_passing(TeamFilter.trenchFit, pit: pit, teams: [1, 2, 3, 4]), {
        1,
      });
    });

    test('reads a stringified true', () {
      final pit = {
        1: _pit(1, {'trenchFit': 'true'}),
      };
      expect(_passing(TeamFilter.trenchFit, pit: pit), {1});
    });
  });

  group('climbsL3 and autoClimb', () {
    test('need one successful entry, not a failed or unattempted one', () {
      final entries = [
        _entry(1, {'eHigh': 'Failed'}),
        _entry(1, {'eHigh': 'Successful'}),
        _entry(2, {'eHigh': 'Failed'}),
        _entry(2, {'eHigh': 'N/A'}),
      ];
      expect(_passing(TeamFilter.climbsL3, entries: entries), {1});
    });

    test('a retired position choice and a stored label still count', () {
      final entries = [
        _entry(1, {'eHigh': 'Outpost'}),
        _entry(2, {'eHigh': 'Not Attempted'}),
      ];
      expect(_passing(TeamFilter.climbsL3, entries: entries), {1});
    });

    test('auto climb reads auLow, not eHigh', () {
      final entries = [
        _entry(1, {'auLow': 'Successful'}),
        _entry(2, {'eHigh': 'Successful'}),
      ];
      expect(_passing(TeamFilter.autoClimb, entries: entries), {1});
      expect(_passing(TeamFilter.climbsL3, entries: entries), {2});
    });

    test('no entries fails', () {
      expect(_passing(TeamFilter.climbsL3), isEmpty);
    });

    test('no config field fails rather than guessing', () {
      final results = TeamFilters.evaluate(
        teams: [1],
        entries: [
          _entry(1, {'eHigh': 'Successful'}),
        ],
        pitByTeam: const {},
        eventKey: _event,
      );
      expect(results.count(TeamFilter.climbsL3), 0);
    });
  });

  group('defense and passer', () {
    test('exactly 30% of 10 entries passes', () {
      final entries = _roleEntries(1, 'tRdefense', 3, 10);
      expect(_passing(TeamFilter.defense, entries: entries), {1});
    });

    test('just under 30% fails', () {
      final entries = _roleEntries(1, 'tRdefense', 2, 7);
      expect(_passing(TeamFilter.defense, entries: entries), isEmpty);
    });

    test('exactly 2 entries is enough, 1 entry is not', () {
      expect(
        _passing(
          TeamFilter.defense,
          entries: _roleEntries(1, 'tRdefense', 1, 2),
        ),
        {1},
      );
      expect(
        _passing(
          TeamFilter.defense,
          entries: _roleEntries(1, 'tRdefense', 1, 1),
        ),
        isEmpty,
      );
    });

    test('entries without the field count in the total', () {
      final entries = [
        _entry(1, {'tRdefense': true}),
        _entry(1, const {}),
        _entry(1, const {}),
        _entry(1, const {}),
      ];
      expect(_passing(TeamFilter.defense, entries: entries), isEmpty);
    });

    test('passer reads tRpasser with the same thresholds', () {
      final entries = [
        ..._roleEntries(1, 'tRpasser', 3, 10),
        ..._roleEntries(2, 'tRpasser', 2, 10),
        ..._roleEntries(2, 'tRdefense', 10, 10),
      ];
      expect(_passing(TeamFilter.passer, entries: entries), {1});
    });
  });

  group('cleanRecord', () {
    test('needs an entry, and no card and no death', () {
      final entries = [
        _entry(1, {'ryCard': 'None', 'dieCard': false}),
        _entry(2, {'ryCard': 'Yellow'}),
        _entry(3, {'dieCard': true}),
      ];
      expect(
        _passing(TeamFilter.cleanRecord, entries: entries, teams: [1, 2, 3, 4]),
        {1},
      );
    });

    test('legacy card values count as a card', () {
      final entries = [
        _entry(1, {'ryCard': true}),
        _entry(2, {'ryCard': 'true'}),
        _entry(3, {'dieCard': 'true'}),
        _entry(4, {'ryCard': 'false', 'dieCard': 'false'}),
      ];
      expect(
        _passing(TeamFilter.cleanRecord, entries: entries, teams: [1, 2, 3, 4]),
        {4},
      );
    });

    test('a card at another event does not count', () {
      final entries = [
        _entry(1, {'ryCard': 'Red'}, key: '2026other_qm1'),
        _entry(1, const {}),
      ];
      expect(_passing(TeamFilter.cleanRecord, entries: entries), {1});
    });
  });

  group('consistent', () {
    List<ScoutEntry> scores(int team, List<num> values) => [
      for (final v in values) _entry(team, {'teleopFuelScored': v}),
    ];

    test('spread exactly 25% of the mean passes', () {
      expect(
        _passing(TeamFilter.consistent, entries: scores(1, [3, 5, 3, 5])),
        {1},
      );
    });

    test('spread over 25% fails', () {
      expect(
        _passing(TeamFilter.consistent, entries: scores(1, [3, 5, 3, 6])),
        isEmpty,
      );
    });

    test('3 entries is enough, 2 is not', () {
      expect(_passing(TeamFilter.consistent, entries: scores(1, [4, 4, 4])), {
        1,
      });
      expect(
        _passing(TeamFilter.consistent, entries: scores(1, [4, 4])),
        isEmpty,
      );
    });

    test('a mean of 0 fails', () {
      expect(
        _passing(TeamFilter.consistent, entries: scores(1, [0, 0, 0])),
        isEmpty,
      );
    });
  });

  group('noPitData', () {
    test('passes teams with no pit entry, not ones with an empty entry', () {
      final pit = {1: _pit(1)};
      expect(_passing(TeamFilter.noPitData, pit: pit), {2});
    });
  });

  group('event scope', () {
    test('entries from another event are ignored', () {
      final entries = [
        _entry(1, {'eHigh': 'Successful'}, key: '2026other_qm1'),
        _entry(2, {'eHigh': 'Successful'}),
      ];
      expect(_passing(TeamFilter.climbsL3, entries: entries), {2});
    });

    test('an entry that names no event is kept', () {
      final noEvent = ScoutEntry(
        matchId: '',
        teamNumber: 1,
        fieldValues: const {'eHigh': 'Successful'},
      );
      expect(_passing(TeamFilter.climbsL3, entries: [noEvent]), {1});
    });

    test('an empty event key keeps everything', () {
      final entries = [
        _entry(1, {'eHigh': 'Successful'}, key: '2026other_qm1'),
      ];
      expect(_passing(TeamFilter.climbsL3, entries: entries, eventKey: ''), {
        1,
      });
    });

    test('teams outside the roster are left out of the counts', () {
      final results = TeamFilters.evaluate(
        teams: [1],
        entries: [
          _entry(1, {'eHigh': 'Successful'}),
          _entry(9, {'eHigh': 'Successful'}),
        ],
        pitByTeam: const {},
        eventKey: _event,
        config: _config,
      );
      expect(results.total, 1);
      expect(results.count(TeamFilter.climbsL3), 1);
    });
  });

  group('TeamFilterResults.passes', () {
    test('combines filters with AND and passes everyone for none', () {
      final entries = [
        _entry(1, {'eHigh': 'Successful'}),
        _entry(2, {'eHigh': 'Successful'}),
      ];
      final pit = {
        1: _pit(1, {'trenchFit': true}),
      };
      final results = TeamFilters.evaluate(
        teams: [1, 2],
        entries: entries,
        pitByTeam: pit,
        eventKey: _event,
        config: _config,
      );
      const both = {TeamFilter.climbsL3, TeamFilter.trenchFit};
      expect(results.passes(1, both), isTrue);
      expect(results.passes(2, both), isFalse);
      expect(results.passes(2, const {}), isTrue);
    });
  });
}
