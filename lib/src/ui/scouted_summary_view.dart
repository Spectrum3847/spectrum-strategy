import 'package:material_ui/material_ui.dart';

import '../scouting/services/scouted_summary.dart';
import '../theme/strategy_palette.dart';

class ScoutedSummaryView extends StatelessWidget {
  const ScoutedSummaryView({required this.summary, super.key});

  final ScoutedSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    if (summary.isEmpty) {
      return Text(
        'Nothing to report yet. This fills in as scout entries arrive.',
        style: text.bodySmall?.copyWith(color: muted),
      );
    }
    final trend = summary.trend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trend != null)
          _Line(
            icon: switch (trend.direction) {
              ScoutedTrend.improving => Icons.trending_up_rounded,
              ScoutedTrend.declining => Icons.trending_down_rounded,
              ScoutedTrend.steady => Icons.trending_flat_rounded,
            },
            line: trend.line,
          ),
        for (final line in summary.strengths)
          _Line(icon: Icons.check_rounded, line: line),
        for (final line in summary.concerns)
          _Line(
            icon: Icons.warning_amber_rounded,
            line: line,
            color: Theme.of(context).colorScheme.error,
          ),
        for (final line in summary.roles)
          _Line(icon: Icons.sports_martial_arts_rounded, line: line),
        const SizedBox(height: 4),
        Text(
          'From ${summary.entryCount} scout '
          '${summary.entryCount == 1 ? 'entry' : 'entries'}. Form fields '
          'only, not comments.',
          style: text.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.line, this.color});

  final IconData icon;
  final ScoutedSummaryLine line;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: text.bodyMedium,
                children: [
                  TextSpan(text: line.text),
                  if (line.matches.isNotEmpty)
                    TextSpan(
                      text: '  ${line.matches.join(', ')}',
                      style: text.bodySmall?.copyWith(
                        color: StrategyPalette.mutedTextOf(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
