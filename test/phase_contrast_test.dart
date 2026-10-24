import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

void main() {
  group('onPhaseColor contrast (phase fill on selected chip)', () {
    for (final phase in StrategyPhase.values) {
      test('${phase.name} fill onPhaseColor clears WCAG AA', () {
        final fill = StrategyPalette.phaseColor(phase);
        final ink = StrategyPalette.onPhaseColor(phase);
        final ratio = StrategyPalette.contrastRatio(ink, fill);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '${phase.name} fill $fill with onPhaseColor $ink gives '
              '${ratio.toStringAsFixed(2)}:1, below the 4.5:1 AA floor',
        );
      });
    }
  });

  group('onPhaseColor chooses the higher-contrast option', () {
    test('auton keeps the light ink', () {
      expect(
        StrategyPalette.onPhaseColor(StrategyPhase.auton),
        StrategyPalette.onPhaseLight,
      );
    });

    test('teleop keeps the light ink', () {
      expect(
        StrategyPalette.onPhaseColor(StrategyPhase.teleop),
        StrategyPalette.onPhaseLight,
      );
    });

    test('endgame flips to the dark ink', () {
      expect(
        StrategyPalette.onPhaseColor(StrategyPhase.endgame),
        StrategyPalette.onPhaseDark,
      );
    });

    test('white on the endgame fill really is below AA', () {
      expect(
        StrategyPalette.contrastRatio(
          StrategyPalette.onPhaseLight,
          StrategyPalette.phaseColor(StrategyPhase.endgame),
        ),
        lessThan(4.5),
      );
    });
  });
}
