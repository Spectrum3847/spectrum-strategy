import 'package:flutter/material.dart';

import '../models/match_forecast.dart';
import '../theme/strategy_palette.dart';

class MatchForecastRow extends StatelessWidget {
  const MatchForecastRow({
    required this.source,
    required this.forecast,
    required this.unreachable,
    super.key,
  });

  final MatchForecastSource source;
  final MatchForecast? forecast;
  final bool unreachable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = StrategyPalette.mutedTextOf(context);
    final value = forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(source.label, style: theme.textTheme.labelLarge),
            ),
            if (value == null)
              Expanded(
                child: Text(
                  unreachable
                      ? 'Could not be reached.'
                      : 'No forecast for this match.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              )
            else
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${value.redScore.round()}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: StrategyPalette.allianceRed,
                        ),
                      ),
                      TextSpan(
                        text: '  -  ',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                      TextSpan(
                        text: '${value.blueScore.round()}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: StrategyPalette.allianceBlue,
                        ),
                      ),
                      TextSpan(
                        text:
                            '   ${value.redFavored ? 'Red' : 'Blue'} '
                            '${(value.favoredWinProbability * 100).round()}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 6),
          _ProbabilityBar(redWinProbability: value.redWinProbability),
        ],
      ],
    );
  }
}

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({required this.redWinProbability});

  final double redWinProbability;

  @override
  Widget build(BuildContext context) {
    final redPercent = (redWinProbability * 100).round();
    return Semantics(
      label: 'Red win probability $redPercent percent',
      child: ClipRRect(
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        child: SizedBox(
          height: 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: redPercent.clamp(1, 99),
                child: const ColoredBox(color: StrategyPalette.allianceRed),
              ),
              Expanded(
                flex: (100 - redPercent).clamp(1, 99),
                child: const ColoredBox(color: StrategyPalette.allianceBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
