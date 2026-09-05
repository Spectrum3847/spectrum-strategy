import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../models/match_preview.dart';
import '../services/assistant/assistant_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/post_match_report_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import 'post_match_report_screen.dart';

class MatchPreviewScreen extends StatelessWidget {
  const MatchPreviewScreen({
    required this.preview,
    this.eventKey = '',
    this.postMatchReportController,
    this.userRoleController,
    this.cycleLogController,
    this.tbaClient,
    this.myTeamNumber,
    this.assistant,
    super.key,
  });

  final MatchPreview preview;

  final String eventKey;

  final PostMatchReportController? postMatchReportController;

  final UserRoleController? userRoleController;

  final CycleLogController? cycleLogController;

  final TbaClient? tbaClient;

  final int? myTeamNumber;

  final AssistantService? assistant;

  String get _matchId {
    final key = preview.matchKey;
    final prefix = '${eventKey}_';
    return key.startsWith(prefix) ? key.substring(prefix.length) : key;
  }

  Future<void> _openReport(BuildContext context) async {
    final controller = postMatchReportController;
    if (controller == null || eventKey.isEmpty) return;
    final teams = <int>[
      for (final team in preview.red) team.teamNumber,
      for (final team in preview.blue) team.teamNumber,
    ];
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PostMatchReportScreen(
          controller: controller,
          matchLabel: preview.matchLabel,
          eventKey: eventKey,
          matchId: _matchId,
          userRoleController: userRoleController,
          cycleLogController: cycleLogController,
          cycleLogTeams: teams,
          tbaClient: tbaClient,
          myTeamNumber: myTeamNumber,
          assistant: assistant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canReport = postMatchReportController != null && eventKey.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('${preview.matchLabel} preview'),
        actions: <Widget>[
          if (canReport)
            IconButton(
              icon: const Icon(Icons.rate_review_outlined),
              tooltip: 'Post match report',
              onPressed: () => _openReport(context),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _PurposeLine(),
            const SizedBox(height: 12),
            if (preview.unscouted.isNotEmpty) ...[
              _UnscoutedNotice(teams: preview.unscouted),
              const SizedBox(height: 16),
            ],
            MatchPreviewColumns(preview: preview),
          ],
        ),
      ),
    );
  }
}

class _PurposeLine extends StatelessWidget {
  const _PurposeLine();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Text(
      'For the strategy call before this match plays: EPA and your own '
      'scouting for all six robots, side by side.',
      style: style?.copyWith(color: StrategyPalette.mutedTextOf(context)),
    );
  }
}

class _UnscoutedNotice extends StatelessWidget {
  const _UnscoutedNotice({required this.teams});

  final List<MatchPreviewTeam> teams;

  @override
  Widget build(BuildContext context) {
    final numbers = teams
        .map((MatchPreviewTeam t) => t.teamNumber.toString())
        .join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.visibility_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Not scouted yet: $numbers')),
        ],
      ),
    );
  }
}

class MatchPreviewColumns extends StatelessWidget {
  const MatchPreviewColumns({required this.preview, super.key});

  final MatchPreview preview;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _alliance(
            context,
            label: 'Red',
            teams: preview.red,
            epa: preview.redEpa,
            isRed: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _alliance(
            context,
            label: 'Blue',
            teams: preview.blue,
            epa: preview.blueEpa,
            isRed: false,
          ),
        ),
      ],
    );
  }

  Widget _alliance(
    BuildContext context, {
    required String label,
    required List<MatchPreviewTeam> teams,
    required double? epa,
    required bool isRed,
  }) {
    final tone = isRed
        ? StrategyPalette.allianceRed
        : StrategyPalette.allianceBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(width: 10, height: 10, color: tone),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Text(
              epa == null ? 'EPA --' : 'EPA ${epa.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final team in teams) ...[
          _TeamRow(team: team),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});

  final MatchPreviewTeam team;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                team.teamNumber.toString(),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                team.epaTotal == null
                    ? 'EPA --'
                    : '${team.epaTotal!.toStringAsFixed(1)} EPA',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          if (team.nickname.isNotEmpty)
            Text(
              team.nickname,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: muted),
            ),
          const SizedBox(height: 4),
          Text(
            team.isScouted
                ? 'Scouted ${team.matchesScouted}x, '
                      'avg ${team.scoutedScore!.toStringAsFixed(1)}'
                : 'Not scouted',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: team.isScouted
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
