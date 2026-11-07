import 'package:statbotics_client/statbotics_client.dart';

import 'assistant_backend.dart';

class TeamAwardRow {
  const TeamAwardRow({
    required this.name,
    required this.eventKey,
    required this.year,
    required this.isWinOrFinalist,
  });

  factory TeamAwardRow.fromJson(Map<String, dynamic> json) => TeamAwardRow(
    name: json['name'] as String? ?? '',
    eventKey: json['eventKey'] as String? ?? '',
    year: (json['year'] as num?)?.toInt() ?? 0,
    isWinOrFinalist: json['isWinOrFinalist'] as bool? ?? false,
  );

  final String name;
  final String eventKey;
  final int year;

  final bool isWinOrFinalist;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'eventKey': eventKey,
    'year': year,
    'isWinOrFinalist': isWinOrFinalist,
  };
}

class TeamAlliancePlacement {
  const TeamAlliancePlacement({
    required this.eventKey,
    required this.allianceNumber,
    required this.pickIndex,
    required this.roundReached,
  });

  factory TeamAlliancePlacement.fromJson(Map<String, dynamic> json) =>
      TeamAlliancePlacement(
        eventKey: json['eventKey'] as String? ?? '',
        allianceNumber: (json['allianceNumber'] as num?)?.toInt() ?? 0,
        pickIndex: (json['pickIndex'] as num?)?.toInt() ?? 0,
        roundReached: json['roundReached'] as String? ?? '',
      );

  final String eventKey;

  final int allianceNumber;

  final int pickIndex;

  final String roundReached;

  bool get isCaptain => pickIndex == 0;

  String get role => switch (pickIndex) {
    0 => 'alliance captain',
    1 => 'first pick',
    2 => 'second pick',
    _ => 'backup',
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eventKey': eventKey,
    'allianceNumber': allianceNumber,
    'pickIndex': pickIndex,
    'roundReached': roundReached,
  };
}

class TeamBriefInputs {
  const TeamBriefInputs({
    this.seasons = const <StatboticsTeamYear>[],
    this.events = const <StatboticsTeamEvent>[],
    this.awards = const <TeamAwardRow>[],
    this.alliances = const <TeamAlliancePlacement>[],
  });

  final List<StatboticsTeamYear> seasons;

  final List<StatboticsTeamEvent> events;

  final List<TeamAwardRow> awards;

  final List<TeamAlliancePlacement> alliances;

  List<int> get years {
    final seen = <int>{
      ...seasons.map((s) => s.year),
      ...events.map((e) => e.year),
    };
    return seen.toList()..sort();
  }

  bool get isEmpty =>
      seasons.isEmpty && events.isEmpty && awards.isEmpty && alliances.isEmpty;
}

class TeamBrief {
  const TeamBrief._();

  static const int minimumEvents = 2;

  static const int fullBriefEvents = 4;

  static int wordLimitFor(int events) => events >= fullBriefEvents ? 200 : 90;

  static AssistantRequest? request({
    required int teamNumber,
    required TeamBriefInputs inputs,
  }) {
    if (inputs.events.length < minimumEvents) {
      return null;
    }
    return AssistantRequest(
      cacheKey: cacheKeyFor(teamNumber: teamNumber, inputs: inputs),
      system: _system,
      prompt: _prompt(teamNumber, inputs),
      coverage: inputs.events.length,

      minimumChars: inputs.events.length >= fullBriefEvents ? 200 : 100,
    );
  }

  static String cacheKeyFor({
    required int teamNumber,
    required TeamBriefInputs inputs,
  }) {
    final events = inputs.events.map((e) => e.event).toList()..sort();
    return 'team-brief:$teamNumber:${events.join(',')}';
  }

  static const String _system =
      'You write a short brief on one FRC team\'s history for a drive coach '
      'to read before an alliance meeting. You are given finished numbers; '
      'your job is to say what they mean, never to recompute them. '
      'Every sentence must name the event or season it comes from. If you '
      'cannot point at a specific row you were given, do not write the claim '
      'at all: drop it rather than softening it, because a coach may repeat '
      'it out loud to another team. Do not infer anything about a robot\'s '
      'mechanisms, its drivers, its scouting reputation or its intentions '
      'from a rank or a win-loss record, and do not describe a team as '
      'unreliable, inconsistent or weak unless a number you were given shows '
      'it and you cite that number. Compare seasons only on the unitless or '
      'normalized EPA scale, or on world rank, never on EPA points, which '
      'mean different things in different games. '
      'A lower rank number is better than a higher one, for world rank and '
      'for qualification rank alike, so rank 222 is a better season than '
      'rank 307 and moving to a lower number is an improvement, never a '
      'concern. '
      'Use each alliance role exactly as it is given to you: a first pick is '
      'not a captain, and a captain is not a pick. Do not upgrade or '
      'downgrade a role to make a sentence read better. '
      'Say plainly when the history '
      'is too thin to support a section, and leave that section out.';

  static String _prompt(int teamNumber, TeamBriefInputs inputs) {
    final buffer = StringBuffer()
      ..writeln(
        'Write a brief on FRC team $teamNumber from the history below. Use '
        'exactly these three headings, and drop any heading you cannot '
        'support from the rows given:',
      )
      ..writeln()
      ..writeln(
        'How they perform: two or three lines on what their results say '
        'about them, citing events.',
      )
      ..writeln(
        'How they got there: how their qualification rank and record at each '
        'event turned into the position they finished in. An award named '
        'Winner or Finalist is a playoff result; a judged award is not.',
      )
      ..writeln(
        'Watch out for: at most three specific things a coach should know, '
        'each one citing the event or season that shows it. Only these count '
        'as a thing to flag, and only when the rows show it: a losing '
        'win-loss record at an event, a qualification rank far worse than '
        'this team\'s own other events, one phase of the split much weaker '
        'than the others, or a season whose world rank is well below the '
        'other. If none of those apply, write exactly "Nothing in these '
        'results stands out to flag." and nothing else under this heading. '
        'Do not comment on your own reasoning or on whether the data '
        'supports you. Do not turn a low rank or a losing record into a '
        'claim about drivers, reliability or robot design: report the '
        'number and let the coach judge it.',
      )
      ..writeln()
      ..writeln(
        'Keep the whole thing under ${wordLimitFor(inputs.events.length)} '
        'words. Numbers below are already computed. A rank is where the team '
        'finished qualification at that event, not where it placed overall, '
        'so do not call rank 2 a second-place finish.',
      );

    if (inputs.events.length < fullBriefEvents) {
      buffer
        ..writeln()
        ..writeln(
          'This team has only ${inputs.events.length} events on record, '
          'which is thin. Say so in the first line, keep every section to '
          'one sentence, and do not describe a pattern: with this few events '
          'there are results, not tendencies.',
        );
    }

    if (inputs.seasons.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Seasons (EPA, newest first):');
      for (final season in inputs.seasons) {
        buffer.writeln('- ${_seasonLine(season)}');
      }
    }

    if (inputs.events.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Events (newest first):');
      for (final event in inputs.events) {
        buffer.writeln('- ${_eventLine(event)}');
      }
    }

    if (inputs.alliances.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Alliance selection (how the field read them):');
      for (final placement in inputs.alliances) {
        final round = placement.roundReached.isEmpty
            ? 'no playoff round recorded'
            : 'reached ${_roundName(placement.roundReached)}';
        buffer.writeln(
          '- ${placement.eventKey}: alliance ${placement.allianceNumber}, '
          '${placement.role}, $round',
        );
      }
    }

    if (inputs.awards.isEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Awards: none in these seasons. That is not itself a weakness, so '
          'do not present it as one.',
        );
    } else {
      buffer
        ..writeln()
        ..writeln('Awards:');
      for (final award in inputs.awards) {
        buffer.writeln(
          '- ${award.year} ${award.eventKey}: ${award.name}'
          '${award.isWinOrFinalist ? ' (playoff result)' : ' (judged award)'}',
        );
      }
    }

    return buffer.toString();
  }

  static String _seasonLine(StatboticsTeamYear season) {
    final parts = <String>[];
    final unitless = season.epa.unitless;
    if (unitless != null) {
      parts.add('unitless EPA ${_n(unitless)}');
    }
    final norm = season.epa.norm;
    if (norm != null) {
      parts.add('normalized EPA ${_n(norm)} (1500 is average)');
    }
    final rank = season.epaRank;
    if (rank != null) {
      final count = season.epaRankTeamCount;
      parts.add(
        count == null ? 'world rank $rank' : 'world rank $rank of $count',
      );
    }
    parts.add('record ${season.wins}-${season.losses}-${season.ties}');
    return '${season.year}: ${parts.join(', ')}';
  }

  static String _eventLine(StatboticsTeamEvent event) {
    final parts = <String>[];
    final rank = event.rank;
    if (rank != null) {
      final count = event.numTeams;
      parts.add(
        count == null
            ? 'qualification rank $rank'
            : 'qualification rank $rank of $count',
      );
    } else {
      parts.add('no qualification rank recorded');
    }
    parts.add('record ${event.record}');
    final total = event.epa.totalPoints;
    if (total != null) {
      parts.add('EPA ${_n(total)} in that season\'s points');
    }
    final phases = <String>[
      if (event.epa.autoPoints != null) 'auton ${_n(event.epa.autoPoints!)}',
      if (event.epa.teleopPoints != null)
        'teleop ${_n(event.epa.teleopPoints!)}',
      if (event.epa.endgamePoints != null)
        'endgame ${_n(event.epa.endgamePoints!)}',
    ];
    if (phases.isNotEmpty) {
      parts.add('phase split ${phases.join(' / ')}');
    }
    final label = event.eventName.isEmpty ? event.event : event.eventName;
    return '${event.year} ${event.event} ($label): ${parts.join(', ')}';
  }

  static String _roundName(String level) => switch (level) {
    'f' => 'the final',
    'sf' => 'the semifinal',
    'qf' => 'the quarterfinal',
    'ef' => 'the eighthfinal',
    _ => level,
  };

  static String _n(double value) => value.toStringAsFixed(1);
}
