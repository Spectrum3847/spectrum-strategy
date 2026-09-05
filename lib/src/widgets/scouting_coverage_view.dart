import 'package:flutter/material.dart';

import '../services/scouting_coverage.dart';
import '../theme/strategy_palette.dart';
import 'empty_state.dart';

class ScoutingCoverageView extends StatelessWidget {
  const ScoutingCoverageView({
    required this.coverage,
    required this.hasEvent,
    super.key,
  });

  final ScoutingCoverage coverage;

  final bool hasEvent;

  @override
  Widget build(BuildContext context) {
    if (!hasEvent) {
      return const EmptyState(
        icon: Icons.event_outlined,
        message: 'Pick an event on the Prematch tab to see scouting coverage.',
      );
    }
    if (coverage.isEmpty) {
      return const EmptyState(
        icon: Icons.grid_off_outlined,
        message:
            'No qualification schedule for this event yet. Coverage appears '
            'once the match schedule publishes.',
      );
    }

    final open = coverage.incompleteMatches;
    if (open.isEmpty) {
      return EmptyState(
        icon: Icons.done_all_rounded,
        message:
            'Every qualification slot has an entry: '
            '${coverage.totalSlots} of ${coverage.totalSlots}.',
      );
    }

    final missingSlots = coverage.totalSlots - coverage.scoutedSlots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CoverageSummary(
          missingSlots: missingSlots,
          totalSlots: coverage.totalSlots,
          openMatches: open.length,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: open.length,
            separatorBuilder: (context, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _MatchRow(match: open[index]),
          ),
        ),
      ],
    );
  }
}

class _CoverageSummary extends StatelessWidget {
  const _CoverageSummary({
    required this.missingSlots,
    required this.totalSlots,
    required this.openMatches,
  });

  final int missingSlots;
  final int totalSlots;
  final int openMatches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchWord = openMatches == 1 ? 'match' : 'matches';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        '$missingSlots of $totalSlots slots unscouted, across $openMatches '
        '$matchWord.',
        style: theme.textTheme.titleSmall,
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});

  final MatchCoverage match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = <CoverageSlot>[
      for (final slot in match.slots)
        if (!slot.scouted) slot,
    ];

    return Container(
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        border: Border.all(color: StrategyPalette.borderOf(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              'Q${match.matchNumber}',
              style: theme.textTheme.titleSmall,
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final slot in missing) ...[
                    _MissingSlotChip(slot: slot),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${match.scoutedCount}/${match.slots.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingSlotChip extends StatelessWidget {
  const _MissingSlotChip({required this.slot});

  final CoverageSlot slot;

  @override
  Widget build(BuildContext context) {
    final isRed = slot.alliance == 'Red';
    final color = isRed
        ? StrategyPalette.allianceRed
        : StrategyPalette.allianceBlue;
    return Semantics(
      label: '${slot.team}, ${slot.alliance} alliance, not scouted',
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '${slot.team}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
