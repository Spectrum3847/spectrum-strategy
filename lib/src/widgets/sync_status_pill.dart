import 'package:flutter/material.dart';

import '../theme/strategy_palette.dart';

class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({
    required this.label,
    required this.icon,
    this.isFailure = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool isFailure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ink = isFailure ? colorScheme.error : colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondary,
        border: Border.all(
          color: isFailure ? colorScheme.error : colorScheme.outline,
        ),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ink),
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: 8),

              if (constraints.maxWidth.isFinite)
                Flexible(child: text)
              else
                text,
            ],
          );
        },
      ),
    );
  }
}
