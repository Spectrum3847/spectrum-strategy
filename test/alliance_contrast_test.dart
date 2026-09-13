import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color fg, Color bg, double alpha) => Color.fromARGB(
  255,
  ((fg.r * alpha + bg.r * (1 - alpha)) * 255).round(),
  ((fg.g * alpha + bg.g * (1 - alpha)) * 255).round(),
  ((fg.b * alpha + bg.b * (1 - alpha)) * 255).round(),
);

void main() {
  group('alliance tag contrast on a solid fill', () {
    const alliances = {
      'red': StrategyPalette.allianceRed,
      'blue': StrategyPalette.allianceBlue,
    };

    for (final entry in alliances.entries) {
      test('${entry.key} ink on a solid fill clears WCAG AA', () {
        final ratio = _contrast(StrategyPalette.onAlliance, entry.value);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              'onAlliance on ${entry.key} is ${ratio.toStringAsFixed(2)}:1, '
              'below the 4.5:1 AA floor for small text',
        );
      });

      test('${entry.key} on a tint of itself would not have passed', () {
        for (final surface in const [
          StrategyPalette.darkSurface,
          StrategyPalette.darkSurfaceStrong,
        ]) {
          final chip = _over(entry.value, surface, 0.15);
          expect(_contrast(entry.value, chip), lessThan(4.5));
        }
      });
    }
  });

  group('error colour contrast on every surface', () {
    const lightSurfaces = {
      'background': StrategyPalette.background,
      'surface': StrategyPalette.surface,
      'surfaceStrong': StrategyPalette.surfaceStrong,
    };
    const darkSurfaces = {
      'darkBackground': StrategyPalette.darkBackground,
      'darkSurface': StrategyPalette.darkSurface,
      'darkSurfaceStrong': StrategyPalette.darkSurfaceStrong,
    };

    for (final entry in lightSurfaces.entries) {
      test('light error ink clears AA on ${entry.key}', () {
        expect(
          _contrast(StrategyPalette.error, entry.value),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    for (final entry in darkSurfaces.entries) {
      test('dark error ink clears AA on ${entry.key}', () {
        expect(
          _contrast(StrategyPalette.darkError, entry.value),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('onError clears AA on its own error fill, per theme', () {
      expect(
        _contrast(StrategyPalette.onError, StrategyPalette.error),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(StrategyPalette.darkOnError, StrategyPalette.darkError),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('error ink is not mistakable for allianceRed', () {
      final errorHue = HSLColor.fromColor(StrategyPalette.error).hue;
      final allianceHue = HSLColor.fromColor(StrategyPalette.allianceRed).hue;
      expect((errorHue - allianceHue).abs(), greaterThanOrEqualTo(12.0));
    });
  });
}
