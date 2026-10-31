import 'package:flutter/material.dart';

import '../models/match_preview.dart';
import '../theme/strategy_palette.dart';
import '../widgets/alliance_tag.dart';

class UnscoutedNotice extends StatelessWidget {
  const UnscoutedNotice({required this.teams, super.key});

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
  const MatchPreviewColumns({required this.preview, this.onTeamTap, super.key});

  final MatchPreview preview;

  final ValueChanged<int>? onTeamTap;

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
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _alliance(
            context,
            label: 'Blue',
            teams: preview.blue,
            epa: preview.blueEpa,
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: AllianceTag(alliance: label),
        ),
        const SizedBox(height: 4),
        Text(
          epa == null ? 'EPA --' : 'EPA ${epa.toStringAsFixed(1)}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        for (final team in teams) ...[
          _TeamRow(
            team: team,
            onTap: onTeamTap == null ? null : () => onTeamTap!(team.teamNumber),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, this.onTap});

  final MatchPreviewTeam team;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      color: StrategyPalette.surfaceOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
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
        ),
      ),
    );
  }
}
