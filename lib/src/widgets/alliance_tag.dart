import 'package:flutter/material.dart';

import '../theme/strategy_palette.dart';

class AllianceTag extends StatelessWidget {
  const AllianceTag({required this.alliance, this.width, super.key});

  final String alliance;

  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: width == null ? null : Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: width == null ? 8 : 0,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: StrategyPalette.allianceColor(alliance),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Text(
        alliance,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: StrategyPalette.onAlliance,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
