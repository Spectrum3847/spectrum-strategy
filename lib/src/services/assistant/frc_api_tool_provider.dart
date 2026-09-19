import 'dart:convert';

import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import '../statbotics/team_history_service.dart';
import 'assistant_tool.dart';
import 'tool_arguments.dart';

class FrcApiToolProvider implements AssistantToolProvider {
  FrcApiToolProvider({
    required this._tba,
    required this._statbotics,
    required this._teamHistory,
  });

  final TbaClient _tba;
  final StatboticsClient _statbotics;
  final TeamHistoryService _teamHistory;

  static const String frcTeamHistory = 'frc_team_history';
  static const String frcEventTeamList = 'frc_event_team_list';
  static const String frcEventMatches = 'frc_event_matches';

  static const int _maxSeasons = 10;
  static const int _minMatchNumber = 1;
  static const int _maxMatchNumber = 200;

  @override
  Future<List<AssistantToolSpec>> tools() async => <AssistantToolSpec>[
    AssistantToolSpec(
      name: frcTeamHistory,
      description:
          'A team\'s official season and per-event history: Statbotics EPA '
          '(unitless, normalized, and world rank), qualification rank and '
          'record per event, team awards, and alliance-selection placement.',
      guidance:
          'Use this for a team\'s public track record. Prefer '
          'scouting_team_summary for what our own scouts observed this '
          'event, since the two overlap.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'team_number': <String, dynamic>{
            'type': 'integer',
            'description': 'The FRC team number, e.g. 3847.',
          },
          'seasons': <String, dynamic>{
            'type': 'integer',
            'description':
                'How many recent seasons to include, 1-$_maxSeasons. '
                'Defaults to 2.',
          },
        },
        'required': <String>['team_number'],
      },
    ),
    AssistantToolSpec(
      name: frcEventTeamList,
      description: 'Every team at one event with its Statbotics rank and EPA.',
      guidance:
          'Use this to answer a question about who is at an event or how the '
          'field ranks, not for one team\'s own history.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'event_key': <String, dynamic>{
            'type': 'string',
            'description': 'The event key, e.g. "2026txhou".',
          },
        },
        'required': <String>['event_key'],
      },
    ),
    AssistantToolSpec(
      name: frcEventMatches,
      description:
          'The official match schedule and results at one event, from The '
          'Blue Alliance. Optionally narrow to one team or a match-number '
          'range.',
      guidance:
          'Use this for official scores and alliances, not for a scout\'s '
          'written account of a match.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'event_key': <String, dynamic>{
            'type': 'string',
            'description': 'The event key, e.g. "2026txhou".',
          },
          'team_number': <String, dynamic>{
            'type': 'integer',
            'description': 'Optional. Only matches this team played in.',
          },
          'match_number_min': <String, dynamic>{
            'type': 'integer',
            'description':
                'Optional. Lowest qualification match number to include, '
                '$_minMatchNumber-$_maxMatchNumber.',
          },
          'match_number_max': <String, dynamic>{
            'type': 'integer',
            'description':
                'Optional. Highest qualification match number to include, '
                '$_minMatchNumber-$_maxMatchNumber.',
          },
        },
        'required': <String>['event_key'],
      },
    ),
  ];

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) async {
    switch (name) {
      case frcTeamHistory:
        return _teamHistoryResult(arguments);
      case frcEventTeamList:
        return _eventTeamList(arguments);
      case frcEventMatches:
        return _eventMatches(arguments);
      default:
        throw ToolArgumentError('FrcApiToolProvider has no tool "$name".');
    }
  }

  Future<String> _teamHistoryResult(Map<String, dynamic> arguments) async {
    final teamNumber = requireTeamNumber(arguments, 'team_number');
    final seasons =
        optionalBoundedInt(arguments, 'seasons', min: 1, max: _maxSeasons) ??
        TeamHistoryService.defaultSeasonCount;
    final inputs = await _teamHistory.briefInputsFor(
      teamNumber,
      seasons: seasons,
    );
    if (inputs.isEmpty) {
      return 'No Statbotics/TBA history found for team $teamNumber.';
    }
    return jsonEncode(<String, dynamic>{
      'teamNumber': teamNumber,
      'seasons': [for (final season in inputs.seasons) season.toJson()],
      'events': [for (final event in inputs.events) event.toJson()],
      'awards': [for (final award in inputs.awards) award.toJson()],
      'alliances': [for (final alliance in inputs.alliances) alliance.toJson()],
    });
  }

  Future<String> _eventTeamList(Map<String, dynamic> arguments) async {
    final eventKey = requireEventKey(arguments, 'event_key');
    final teams = await _statbotics.getEventTeams(eventKey);
    if (teams.isEmpty) {
      return 'No Statbotics team list found for event $eventKey.';
    }
    final sorted = List<StatboticsTeamEvent>.from(teams)
      ..sort((a, b) => (a.rank ?? 1 << 30).compareTo(b.rank ?? 1 << 30));
    return jsonEncode(<String, dynamic>{
      'eventKey': eventKey,
      'teams': [
        for (final team in sorted)
          <String, dynamic>{
            'teamNumber': team.team,
            'teamName': team.teamName,
            'rank': team.rank,
            'record': team.record,
            'epaTotal': team.epa.totalPoints,
          },
      ],
    });
  }

  Future<String> _eventMatches(Map<String, dynamic> arguments) async {
    final eventKey = requireEventKey(arguments, 'event_key');
    final teamNumber = optionalTeamNumber(arguments, 'team_number');
    final min = optionalBoundedInt(
      arguments,
      'match_number_min',
      min: _minMatchNumber,
      max: _maxMatchNumber,
    );
    final max = optionalBoundedInt(
      arguments,
      'match_number_max',
      min: _minMatchNumber,
      max: _maxMatchNumber,
    );
    if (min != null && max != null && min > max) {
      throw const ToolArgumentError(
        '"match_number_min" must not be greater than "match_number_max".',
      );
    }

    final matches = await _tba.getEventMatches(eventKey);
    final filtered = matches
        .where((match) {
          if (teamNumber != null &&
              !match.redTeams.contains(teamNumber) &&
              !match.blueTeams.contains(teamNumber)) {
            return false;
          }
          if (min != null && match.matchNumber < min) return false;
          if (max != null && match.matchNumber > max) return false;
          return true;
        })
        .toList(growable: false);

    if (filtered.isEmpty) {
      return 'No matches found for event $eventKey with those filters.';
    }
    return jsonEncode(<String, dynamic>{
      'eventKey': eventKey,
      'matches': [
        for (final match in filtered)
          <String, dynamic>{
            'level': match.compLevel,
            'matchNumber': match.matchNumber,
            'redTeams': match.redTeams,
            'blueTeams': match.blueTeams,
            'redScore': match.redScore,
            'blueScore': match.blueScore,
            'winningAlliance': match.winningAlliance,
            'played': match.isPlayed,
          },
      ],
    });
  }
}
