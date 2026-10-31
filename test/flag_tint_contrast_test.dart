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

void main() {
  const lightTints = <String, Color>{
    'flagSevere': StrategyPalette.flagSevere,
    'flagWarn': StrategyPalette.flagWarn,
    'flagNotice': StrategyPalette.flagNotice,
  };
  const darkTints = <String, Color>{
    'darkFlagSevere': StrategyPalette.darkFlagSevere,
    'darkFlagWarn': StrategyPalette.darkFlagWarn,
    'darkFlagNotice': StrategyPalette.darkFlagNotice,
  };

  group('light theme ink on a flagged row', () {
    for (final tint in lightTints.entries) {
      for (final ink in const <String, Color>{
        'textPrimary': StrategyPalette.textPrimary,
        'textMuted': StrategyPalette.textMuted,
      }.entries) {
        test('${ink.key} on ${tint.key} clears WCAG AA', () {
          final ratio = _contrast(ink.value, tint.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${ink.key} on ${tint.key} is ${ratio.toStringAsFixed(2)}:1, '
                'below the 4.5:1 AA floor for small text',
          );
        });
      }
    }
  });

  group('dark theme ink on a flagged row', () {
    for (final tint in darkTints.entries) {
      for (final ink in const <String, Color>{
        'darkText': StrategyPalette.darkText,
        'darkTextMuted': StrategyPalette.darkTextMuted,
      }.entries) {
        test('${ink.key} on ${tint.key} clears WCAG AA', () {
          final ratio = _contrast(ink.value, tint.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${ink.key} on ${tint.key} is ${ratio.toStringAsFixed(2)}:1, '
                'below the 4.5:1 AA floor for small text',
          );
        });
      }
    }
  });

  test('no two tints are the same colour', () {
    expect(lightTints.values.toSet(), hasLength(lightTints.length));
    expect(darkTints.values.toSet(), hasLength(darkTints.length));
  });

  test('a flagged row reads as different from an unflagged one', () {
    for (final tint in lightTints.values) {
      expect(_contrast(tint, StrategyPalette.background), greaterThan(1.03));
      expect(_contrast(tint, StrategyPalette.surface), greaterThan(1.03));
    }
    for (final tint in darkTints.values) {
      expect(
        _contrast(tint, StrategyPalette.darkBackground),
        greaterThan(1.03),
      );
      expect(_contrast(tint, StrategyPalette.darkSurface), greaterThan(1.03));
    }
  });
}
