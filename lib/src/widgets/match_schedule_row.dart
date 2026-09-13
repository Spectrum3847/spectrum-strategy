import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/strategy_palette.dart';

const kMatchCompLevelOrder = <String>['qm', 'ef', 'qf', 'sf', 'f'];

List<StatboticsMatch> sortMatchesByCompLevel(List<StatboticsMatch> matches) {
  int rank(String level) {
    final index = kMatchCompLevelOrder.indexOf(level);
    return index < 0 ? kMatchCompLevelOrder.length : index;
  }

  return matches.toList()..sort((a, b) {
    final byLevel = rank(a.compLevel).compareTo(rank(b.compLevel));
    return byLevel != 0 ? byLevel : a.matchNumber.compareTo(b.matchNumber);
  });
}

class MatchScheduleRow extends StatelessWidget {
  const MatchScheduleRow({
    required this.match,
    required this.nicknames,
    this.onTap,
    this.selected = false,
    this.tbaMatch,
    this.showResult = false,
    this.showVideo = false,
    this.showRankingPoints = false,
    this.prediction,
    this.showPrediction = false,
    super.key,
  });

  final StatboticsMatch match;

  final Map<int, String> nicknames;

  final VoidCallback? onTap;
  final bool selected;

  final TbaScheduleMatch? tbaMatch;

  final bool showResult;

  final bool showVideo;

  final bool showRankingPoints;

  final TbaMatchPrediction? prediction;

  final bool showPrediction;

  TbaMatchPrediction? get _livePrediction {
    if (!showPrediction) return null;
    if (tbaMatch?.redScore != null || tbaMatch?.blueScore != null) return null;
    return prediction;
  }

  String get _predictionFooter {
    final p = _livePrediction;
    if (p == null || p.winningAlliance.isEmpty) return '';
    final side = p.winningAlliance == 'red' ? 'Red' : 'Blue';
    final percent = (p.probability * 100).round();
    return 'TBA predicts $side, $percent%';
  }

  String get _footer {
    if (!showResult) return '';
    final tba = tbaMatch;
    if (tba == null) return '';
    final actual = tba.actualTime;
    if (actual != null) return 'Played ${_time(actual)}';
    final predicted = tba.predictedTime;
    if (predicted != null) return 'Expected ${_time(predicted)}';
    final scheduled = tba.scheduledTime;
    if (scheduled != null) return 'Scheduled ${_time(scheduled)}';
    return '';
  }

  static String _time(DateTime utc) {
    final local = utc.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $meridiem';
  }

  int? _rankingPoints(String alliance) {
    final value = tbaMatch?.scoreBreakdown[alliance]?['rp'];
    return value is num ? value.toInt() : null;
  }

  String? get _videoUrl {
    if (!showVideo) return null;
    final videos = tbaMatch?.videos ?? const <TbaMatchVideo>[];
    if (videos.isEmpty) return null;
    for (final video in videos) {
      if (video.type == 'youtube' && video.key.isNotEmpty) {
        return 'https://www.youtube.com/watch?v=${video.key}';
      }
    }
    return 'https://www.thebluealliance.com/match/${match.key}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      onTap: onTap,
      isThreeLine: true,
      title: Text(
        match.displayName,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AllianceLine(
              label: 'Red',
              color: StrategyPalette.allianceRed,
              teams: match.redTeams,
              nicknames: nicknames,
              score: showResult ? tbaMatch?.redScore : null,
              won: tbaMatch?.winningAlliance == 'red',
              rankingPoints: showRankingPoints ? _rankingPoints('red') : null,
              predictedScore: _livePrediction?.redScore,
            ),
            const SizedBox(height: 4),
            _AllianceLine(
              label: 'Blue',
              color: StrategyPalette.allianceBlue,
              teams: match.blueTeams,
              nicknames: nicknames,
              score: showResult ? tbaMatch?.blueScore : null,
              won: tbaMatch?.winningAlliance == 'blue',
              rankingPoints: showRankingPoints ? _rankingPoints('blue') : null,
              predictedScore: _livePrediction?.blueScore,
            ),
            if (_predictionFooter.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _predictionFooter,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
              ),
            ],
            if (_footer.isNotEmpty || _videoUrl != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _footer,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StrategyPalette.mutedTextOf(context),
                      ),
                    ),
                  ),
                  if (_videoUrl != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(_videoUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Video'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllianceLine extends StatelessWidget {
  const _AllianceLine({
    required this.label,
    required this.color,
    required this.teams,
    required this.nicknames,
    this.score,
    this.won = false,
    this.rankingPoints,
    this.predictedScore,
  });

  final String label;
  final Color color;
  final List<int> teams;
  final Map<int, String> nicknames;

  final int? score;

  final bool won;

  final int? rankingPoints;

  final double? predictedScore;

  String _teamLabel(int team) {
    final nick = nicknames[team];
    if (nick == null || nick.isEmpty) return team.toString();
    return '$team $nick';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(
              Radius.circular(StrategyPalette.radiusSm),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: StrategyPalette.onAlliance,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            teams.isEmpty ? 'Teams not set' : teams.map(_teamLabel).join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (rankingPoints != null) ...[
          const SizedBox(width: 8),
          Text(
            '${rankingPoints}RP',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: StrategyPalette.mutedTextOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (predictedScore != null) ...[
          const SizedBox(width: 8),
          Text(
            '~${predictedScore!.round()}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: StrategyPalette.mutedTextOf(context),
            ),
          ),
        ],
        if (score != null) ...[
          const SizedBox(width: 8),
          Text(
            '$score',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: won ? FontWeight.w800 : FontWeight.w500),
          ),
        ],
      ],
    );
  }
}
