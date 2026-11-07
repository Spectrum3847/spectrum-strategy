import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../../scouting/services/match_hub_stats.dart';
import '../../services/tba/fetch_tba_match.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/alliance_tag.dart';
import '../match_prediction_view.dart' show MatchForecastCard;
import '../match_preview_columns.dart';
import '../post_match_report_screen.dart';
import 'match_hub_launcher.dart';
import 'match_hub_stat_table.dart';
import 'match_hub_widgets.dart';

class MatchHubMatchTab extends StatefulWidget {
  const MatchHubMatchTab({
    required this.launcher,
    required this.data,
    super.key,
  });

  final MatchHubLauncher launcher;
  final MatchHubData data;

  @override
  State<MatchHubMatchTab> createState() => _MatchHubMatchTabState();
}

class _MatchHubMatchTabState extends State<MatchHubMatchTab> {
  Future<TbaScheduleMatch?>? _result;

  @override
  void initState() {
    super.initState();
    final events = widget.launcher.eventController;
    final client = events.tbaClient;
    _result = client == null
        ? null
        : fetchTbaMatch(client, events.eventKey, widget.data.match.key);

    unawaited(Future<void>.microtask(events.loadForecasts));
  }

  Future<void> _openReport() async {
    final launcher = widget.launcher;
    final controller = launcher.postMatchReportController;
    if (controller == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => PostMatchReportScreen(
          controller: controller,
          matchLabel: widget.data.preview.matchLabel,
          eventKey: launcher.eventController.eventKey,
          matchId: launcher.matchIdOf(widget.data.match),
          userRoleController: launcher.userRoleController,
          cycleLogController: launcher.cycleLogController,
          cycleLogTeams: <int>[
            for (final team in widget.data.preview.allTeams) team.teamNumber,
          ],
          tbaClient: launcher.eventController.tbaClient,
          myTeamNumber: launcher.eventController.myTeamNumber,
          assistant: launcher.assistant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final launcher = widget.launcher;
    final data = widget.data;
    final events = launcher.eventController;
    return FutureBuilder<TbaScheduleMatch?>(
      future: _result,
      builder: (context, snapshot) {
        final fetched = snapshot.data;
        final result = fetched != null && fetched.isPlayed ? fetched : null;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _StatusLine(
                  played: result != null,
                  ourAlliance: data.ourAlliance,
                ),
                const SizedBox(height: 12),
                if (data.preview.unscouted.isNotEmpty) ...<Widget>[
                  UnscoutedNotice(teams: data.preview.unscouted),
                  const SizedBox(height: 16),
                ],
                if (data.startConflicts.isNotEmpty) ...<Widget>[
                  StartConflictNotice(conflicts: data.startConflicts),
                  const SizedBox(height: 16),
                ],
                MatchPreviewColumns(
                  preview: data.preview,
                  onTeamTap: (team) => launcher.openTeam(context, team),
                ),
                const SizedBox(height: 16),
                HubSection(
                  title: 'Scouted stats',
                  child: MatchHubStatTable(
                    data: data,
                    onOpenTeam: (team) => launcher.openTeam(context, team),
                  ),
                ),
                const SizedBox(height: 16),
                HubSection(
                  title: 'Prediction',
                  child: _Prediction(data: data),
                ),
                const SizedBox(height: 12),
                MatchForecastCard(
                  forecasts: events.forecastsFor(data.match.key),
                  loading: events.forecastsLoading,
                  sourcesMissing: events.forecastSourcesMissing,
                ),
                if (result != null) ...<Widget>[
                  const SizedBox(height: 16),
                  HubSection(
                    title: 'Result',
                    child: _Result(
                      data: data,
                      result: result,
                      launcher: launcher,
                    ),
                  ),
                ],
                if (launcher.postMatchReportController != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _openReport,
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text('Post match report'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.played, required this.ourAlliance});

  final bool played;
  final String? ourAlliance;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              played ? Icons.check_circle_outline : Icons.schedule_rounded,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              played ? 'Played' : 'Upcoming',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        if (ourAlliance != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('We play', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(width: 6),
              AllianceTag(alliance: ourAlliance!),
            ],
          ),
      ],
    );
  }
}

String _points(double? value) =>
    value == null ? '--' : value.toStringAsFixed(1);

class _Prediction extends StatelessWidget {
  const _Prediction({required this.data});

  final MatchHubData data;

  @override
  Widget build(BuildContext context) {
    final scouted = data.preview.allTeams.any((team) => team.isScouted);
    final prediction = data.scoutedPrediction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AllianceValues(
          label: 'Expected points (EPA)',
          red: _points(data.preview.redEpa),
          blue: _points(data.preview.blueEpa),
        ),
        const SizedBox(height: 8),
        if (scouted)
          _AllianceValues(
            label: 'From scouting',
            red: _points(prediction.red.total),
            blue: _points(prediction.blue.total),
          )
        else
          Text(
            'No robot in this match has been scouted yet.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
          ),
      ],
    );
  }
}

class _AllianceValues extends StatelessWidget {
  const _AllianceValues({
    required this.label,
    required this.red,
    required this.blue,
  });

  final String label;
  final String red;
  final String blue;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(label, style: text.labelLarge),
        const AllianceTag(alliance: 'Red'),
        Text(red, style: text.bodyMedium),
        const AllianceTag(alliance: 'Blue'),
        Text(blue, style: text.bodyMedium),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.data,
    required this.result,
    required this.launcher,
  });

  final MatchHubData data;
  final TbaScheduleMatch result;
  final MatchHubLauncher launcher;

  String get _winner => result.isTie
      ? 'Tied'
      : result.winningAlliance == 'red'
      ? 'Red won'
      : 'Blue won';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sides = scoutedVersusOfficial(
      data.match,
      scoutEntries: launcher.scoutingController.entries,
      redOfficial: result.redScore,
      blueOfficial: result.blueScore,
      config: launcher.configController.config,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(_winner, style: text.labelLarge),
        const SizedBox(height: 8),
        _ResultSide(alliance: 'Red', side: sides.red),
        const SizedBox(height: 8),
        _ResultSide(alliance: 'Blue', side: sides.blue),
        const SizedBox(height: 8),
        Text(
          'Scouted is the summed score of the scouted robots in this match, '
          'not official points. A low figure usually means robots went '
          'unscouted.',
          style: text.bodySmall?.copyWith(
            color: StrategyPalette.mutedTextOf(context),
          ),
        ),
      ],
    );
  }
}

class _ResultSide extends StatelessWidget {
  const _ResultSide({required this.alliance, required this.side});

  final String alliance;
  final MatchScoutedSide side;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AllianceTag(alliance: alliance),
        Text('Official ${side.officialScore ?? '--'}', style: text.bodyMedium),
        Text(
          'Scouted ${_points(side.scoutedTotal)} from '
          '${side.scoutedRobots} of ${side.teamScores.length} robots',
          style: text.bodyMedium,
        ),
      ],
    );
  }
}
