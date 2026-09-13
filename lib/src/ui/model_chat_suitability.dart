library;

import 'package:flutter/material.dart';

import '../theme/strategy_palette.dart';

class ModelChatSuitabilityChip extends StatelessWidget {
  const ModelChatSuitabilityChip({super.key});

  static const String label = 'Best for summaries';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class ModelChatSuitabilityNote extends StatelessWidget {
  const ModelChatSuitabilityNote({super.key});

  static const String text =
      'Reliable for a single generated answer, but a model this small can '
      'lose the thread in a chat once a wrong answer is already in it.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
