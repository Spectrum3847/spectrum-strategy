import 'package:flutter/material.dart';

import '../scouting/services/entry_flags.dart';
import '../theme/strategy_palette.dart';

Color entryFlagTint(BuildContext context, EntryFlagKind kind) => switch (kind) {
  EntryFlagKind.duplicateTeam => StrategyPalette.flagSevereOf(context),
  EntryFlagKind.duplicateStation => StrategyPalette.flagWarnOf(context),
  EntryFlagKind.matchNumberOffSchedule => StrategyPalette.flagNoticeOf(context),
};

String entryFlagLabel(EntryFlagKind kind) => switch (kind) {
  EntryFlagKind.duplicateTeam => 'Same team',
  EntryFlagKind.duplicateStation => 'Same station',
  EntryFlagKind.matchNumberOffSchedule => 'Match number',
};

IconData entryFlagIcon(EntryFlagKind kind) => switch (kind) {
  EntryFlagKind.duplicateTeam => Icons.error_outline_rounded,
  EntryFlagKind.duplicateStation => Icons.warning_amber_rounded,
  EntryFlagKind.matchNumberOffSchedule => Icons.help_outline_rounded,
};

class EntryFlagBadge extends StatelessWidget {
  const EntryFlagBadge({required this.flags, super.key});

  final List<EntryFlag> flags;

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) return const SizedBox.shrink();
    final worst = flags.first;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Tooltip(
      message: flags.map((EntryFlag flag) => flag.reason).join('\n'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            entryFlagIcon(worst.kind),
            size: 16,
            color: colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              entryFlagLabel(worst.kind),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
