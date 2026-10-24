import 'package:flutter/material.dart';

import '../scouting/services/team_filters.dart';
import '../theme/strategy_palette.dart';

class TeamFilterBar extends StatelessWidget {
  const TeamFilterBar({
    required this.results,
    required this.active,
    required this.shown,
    required this.showPitFilters,
    required this.onToggle,
    required this.onClear,
    required this.open,
    required this.onOpenChanged,
    super.key,
  });

  final TeamFilterResults results;
  final Set<TeamFilter> active;

  final int shown;

  final bool showPitFilters;
  final void Function(TeamFilter filter, bool selected) onToggle;
  final VoidCallback onClear;

  final bool open;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final selectedColor = StrategyPalette.chipSelectedOf(context);
    final onSelected = StrategyPalette.onChipSelectedOf(context);
    final unselectedColor = StrategyPalette.chipUnselectedOf(context);
    final onUnselected = StrategyPalette.onChipUnselectedOf(context);

    Widget chip(TeamFilter filter) {
      final isOn = active.contains(filter);
      return FilterChip(
        tooltip: filter.rule,
        label: Text('${filter.label} (${results.count(filter)})'),
        selected: isOn,
        onSelected: (value) => onToggle(filter, value),
        backgroundColor: unselectedColor,
        selectedColor: selectedColor,
        checkmarkColor: onSelected,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          color: isOn ? onSelected : onUnselected,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StrategyPalette.radiusSm),
          ),
        ),
      );
    }

    final groups = <Widget>[];
    for (final group in TeamFilterGroup.values) {
      final filters = [
        for (final filter in TeamFilter.values)
          if (filter.group == group && (showPitFilters || !filter.needsPit))
            filter,
      ];
      if (filters.isEmpty) continue;
      groups.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.label,
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final filter in filters) chip(filter)],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => onOpenChanged(!open),
          icon: Icon(
            open ? Icons.expand_less_rounded : Icons.filter_list_rounded,
          ),
          label: Text(
            active.isEmpty ? 'Filters' : 'Filters (${active.length} on)',
          ),
        ),
        if (open) ...groups,
        if (active.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$shown of ${results.total} teams',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
          if (shown == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No team passes every selected filter. Turn one off, or '
                'clear them all to see the full list.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ],
    );
  }
}
