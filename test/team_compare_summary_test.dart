import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/services/assistant/team_compare_summary.dart';

ScoutEntry _entry(int team, {Map<String, dynamic> fieldValues = const {}}) {
  return ScoutEntry(
    matchId: 'session-uuid',
    teamNumber: team,
    fieldValues: fieldValues,
  );
}

const _teleopFuel = ScoutConfigField(
  title: 'Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'teleopFuelScored',
);
const _autoFuel = ScoutConfigField(
  title: 'Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'autoFuelScored',
);

ScoutConfigField _climbLevel(String code) => ScoutConfigField(
  title: 'Climb',
  type: ScoutFieldType.select,
  code: code,
  choices: const <String, String>{
    'N/A': 'Not Attempted',
    'Outpost': 'Outpost',
    'Failed': 'Failed',
    'Successful': 'Successful',
  },
);

ScoutConfig _config() {
  return ScoutConfig(
    title: 'Scout',
    sections: [
      ScoutConfigSection(
        name: 'Scoring',
        fields: [
          _teleopFuel,
          _autoFuel,
          _climbLevel('eLow'),
          _climbLevel('eMiddle'),
          _climbLevel('eHigh'),
        ],
      ),
    ],
  );
}

List<TeamNote> _notes(int count) => [
  for (var i = 0; i < count; i++)
    TeamNote(
      matchId: 'qm$i',
      text: 'note $i',
      author: 'scouter',
      updatedAt: DateTime.utc(2026, 8, 1).add(Duration(minutes: i)),
    ),
];

void main() {
  test('no entries for the team means nothing to summarise', () {
    expect(
      TeamCompareSummary.request(
        teamNumber: 254,
        eventKey: '2026txhou',
        entries: const <ScoutEntry>[],
        notes: const <TeamNote>[],
        config: _config(),
      ),
      isNull,
    );
  });

  test('carries the issue\'s prompt verbatim', () {
    final request = TeamCompareSummary.request(
      teamNumber: 254,
      eventKey: '2026txhou',
      entries: [_entry(254)],
      notes: const <TeamNote>[],
      config: _config(),
    )!;

    expect(request.prompt, contains(TeamCompareSummary.prompt));
  });

  test('the same team at two events does not share a summary', () {
    expect(
      TeamCompareSummary.cacheKeyFor(teamNumber: 254, eventKey: '2026txhou'),
      isNot(
        TeamCompareSummary.cacheKeyFor(teamNumber: 254, eventKey: '2026txdri'),
      ),
    );
  });

  test('the payload carries IQM, cards, disconnects and comments', () {
    final request = TeamCompareSummary.request(
      teamNumber: 254,
      eventKey: '2026txhou',
      entries: [
        _entry(
          254,
          fieldValues: {
            'teleopFuelScored': 30,
            'autoFuelScored': 10,
            'ryCard': true,
            'dieCard': false,
          },
        ),
        _entry(254, fieldValues: {'dieCard': true}),
      ],
      notes: _notes(2),
      config: _config(),
    )!;

    expect(request.prompt, contains('"teamNumber":254'));
    expect(request.prompt, contains('"teleopIqm":30.0'));
    expect(request.prompt, contains('"autoIqm":10.0'));
    expect(request.prompt, contains('"redOrYellowCards":1'));
    expect(request.prompt, contains('"disconnects":1'));
    expect(request.prompt, contains('note 0'));
    expect(request.prompt, contains('note 1'));
    expect(request.coverage, 2);
  });

  test('omits climb success rate when the team never attempted one', () {
    final request = TeamCompareSummary.request(
      teamNumber: 254,
      eventKey: '2026txhou',
      entries: [
        _entry(254, fieldValues: {'eLow': 'N/A'}),
      ],
      notes: const <TeamNote>[],
      config: _config(),
    )!;

    expect(request.prompt, isNot(contains('climbSuccessRate')));
  });

  test('climb success rate is successes over attempts across all levels', () {
    final request = TeamCompareSummary.request(
      teamNumber: 254,
      eventKey: '2026txhou',
      entries: [
        _entry(254, fieldValues: {'eLow': 'Outpost'}),
        _entry(254, fieldValues: {'eMiddle': 'Failed'}),
        _entry(254, fieldValues: {'eHigh': 'N/A'}),
      ],
      notes: const <TeamNote>[],
      config: _config(),
    )!;

    expect(request.prompt, contains('"climbSuccessRate":0.5'));
  });
}
