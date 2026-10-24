import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:tba_client/tba_client.dart';

TbaScheduleMatch tbaMatch(
  int number, {
  required List<int> red,
  required List<int> blue,
  int? redFuel,
  int? blueFuel,
  String compLevel = 'qm',
  String? key,
}) {
  Map<String, dynamic> side(int? fuel) => fuel == null
      ? <String, dynamic>{'totalPoints': 10}
      : <String, dynamic>{
          'hubScore': <String, dynamic>{
            'autoCount': fuel ~/ 4,
            'teleopCount': fuel - fuel ~/ 4,
            'totalCount': fuel,
          },
        };
  return TbaScheduleMatch(
    key: key ?? '2026test_$compLevel$number',
    compLevel: compLevel,
    matchNumber: number,
    redTeams: red,
    blueTeams: blue,
    redScore: 100,
    blueScore: 90,
    scoreBreakdown: <String, Map<String, dynamic>>{
      'red': side(redFuel),
      'blue': side(blueFuel),
    },
  );
}

ScoutEntry fuelEntry(
  int number,
  int team,
  String? scout,
  int fuel, {
  String? matchKey,
  String authorDisplayName = '',
  String authorUid = '',
}) {
  return ScoutEntry(
    matchId: 'session-$number-$team',
    teamNumber: team,
    tbaMatchKey: matchKey ?? '2026test_qm$number',
    authorDisplayName: authorDisplayName,
    authorUid: authorUid,
    fieldValues: <String, dynamic>{
      'scouter': ?scout,
      'autoFuelScored': fuel ~/ 4,
      'teleopFuelScored': fuel - fuel ~/ 4,
    },
  );
}
