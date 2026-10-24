import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/team_incidents.dart';

ScoutEntry _entry(
  int team,
  String match, {
  Object? card,
  Object? died,
  bool typed = false,
}) {
  return ScoutEntry(
    matchId: '',
    teamNumber: team,
    tbaMatchKey: typed ? null : '2026test_$match',
    fieldValues: <String, dynamic>{
      if (typed) 'matchNumber': match,
      'ryCard': ?card,
      'dieCard': ?died,
    },
  );
}

void main() {
  test('lists cards and deaths per team in schedule order', () {
    final incidents = TeamIncidents.byTeam([
      _entry(254, 'qm55', died: true),
      _entry(254, 'qm16', card: 'Yellow'),
      _entry(254, 'qm9', died: true),
      _entry(1678, 'qm3', card: 'None', died: false),
    ]);

    expect(incidents.keys, [254]);
    expect(incidents[254]!.describe(), 'Yellow card Q16 · died Q9, Q55');
    expect(incidents[254]!.weight, 3);
  });

  test('two scouts on one robot count once, at the worse card', () {
    final incidents = TeamIncidents.byTeam([
      _entry(254, 'qm16', card: 'Yellow', died: true),
      _entry(254, 'qm16', card: 'Red', died: 'true'),
    ]);

    final team = incidents[254]!;
    expect(team.red, ['Q16']);
    expect(team.yellow, isEmpty);
    expect(team.died, ['Q16']);
  });

  test('a keyed entry and a typed one for the same match count once', () {
    final incidents = TeamIncidents.byTeam([
      _entry(254, 'qm16', died: true),
      _entry(254, '16', died: true, typed: true),
    ]);

    expect(incidents[254]!.died, ['Q16']);
    expect(incidents[254]!.suggestsDoNotPick, isFalse);
  });

  test('a red card, or two incidents, suggests do-not-pick', () {
    final incidents = TeamIncidents.byTeam([
      _entry(1, 'qm1', card: 'Red'),
      _entry(2, 'qm1', card: 'Yellow'),
      _entry(3, 'qm1', died: true),
      _entry(4, 'qm1', card: 'Yellow'),
      _entry(4, 'qm2', died: true),
      _entry(5, 'qm1', card: true),
      _entry(5, 'qm2', card: 'true'),
    ]);

    expect(incidents[1]!.suggestsDoNotPick, isTrue);
    expect(incidents[2]!.suggestsDoNotPick, isFalse);
    expect(incidents[3]!.suggestsDoNotPick, isFalse);
    expect(incidents[4]!.suggestsDoNotPick, isTrue);
    expect(incidents[5]!.describe(), 'Card Q1, Q2');
    expect(incidents[5]!.suggestsDoNotPick, isTrue);
  });

  test('labels typed numbers and playoff keys', () {
    final incidents = TeamIncidents.byTeam([
      _entry(1, 'f1m2', died: true),
      _entry(1, 'sf4m1', died: true),
      _entry(1, '12', died: true, typed: true),
      _entry(1, 'sf11m1', died: true),
      _entry(1, 'sf2m2', died: true),
      _entry(1, 'QF 3', died: true, typed: true),
    ]);

    expect(incidents[1]!.died, ['Q12', 'QF3', 'SF2-2', 'SF4', 'SF11', 'F2']);
  });

  test('a typed playoff label and its TBA key are one match', () {
    final incidents = TeamIncidents.byTeam([
      _entry(1, 'sf3m1', died: true),
      _entry(1, 'SF3', died: true, typed: true),
      _entry(1, 'f1m2', card: 'Yellow'),
      _entry(1, 'F2', card: 'Yellow', typed: true),
    ]);

    expect(incidents[1]!.died, ['SF3']);
    expect(incidents[1]!.yellow, ['F2']);
  });

  test('a match with no number still counts', () {
    final incidents = TeamIncidents.byTeam([
      ScoutEntry(
        matchId: 'not-a-match',
        teamNumber: 7,
        fieldValues: const <String, dynamic>{'dieCard': true},
      ),
    ]);

    expect(incidents[7]!.describe(), 'Died (no match number)');
  });

  test('entries that name no match are not merged into one', () {
    final incidents = TeamIncidents.byTeam([
      for (var i = 0; i < 2; i++)
        ScoutEntry(
          matchId: '',
          teamNumber: 7,
          fieldValues: const <String, dynamic>{'dieCard': true},
        ),
    ]);

    expect(incidents[7]!.died, hasLength(2));
    expect(incidents[7]!.suggestsDoNotPick, isTrue);
  });
}
