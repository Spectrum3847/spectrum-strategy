import 'package:flutter/material.dart';
import 'package:liquid_glass/liquid_glass.dart';

import '../theme/strategy_palette.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, this.brightness, required this.child});

  final Brightness? brightness;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolvedBrightness = brightness ?? theme.brightness;
    const radius = StrategyPalette.radiusGlassPanel;
    return LiquidGlass(
      key: ValueKey(resolvedBrightness),
      cornerRadius: radius,
      brightness: resolvedBrightness,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
          ),
          child: child,
        ),
      ),
    );
  }
}
