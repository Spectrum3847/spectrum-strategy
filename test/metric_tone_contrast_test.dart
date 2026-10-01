import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

void main() {
  group('metricToneOf contrast', () {
    Future<Color> toneFor(
      WidgetTester tester,
      ThemeData theme,
      double? percentile,
    ) async {
      late Color tone;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              tone = StrategyPalette.metricToneOf(context, percentile);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return tone;
    }

    const tiers = <String, double?>{
      'top': 0.9,
      'middle': 0.5,
      'bottom': 0.1,
      'unranked': null,
    };

    for (final entry in tiers.entries) {
      testWidgets('${entry.key} clears AA on both light card layers', (
        tester,
      ) async {
        final tone = await toneFor(tester, buildAppTheme(), entry.value);
        for (final background in <Color>[
          StrategyPalette.surface,
          StrategyPalette.surfaceStrong,
        ]) {
          final ratio = StrategyPalette.contrastRatio(tone, background);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${entry.key} tone $tone on $background gives '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      });

      testWidgets('${entry.key} clears AA on both dark card layers', (
        tester,
      ) async {
        final tone = await toneFor(tester, buildDarkAppTheme(), entry.value);
        for (final background in <Color>[
          StrategyPalette.darkSurface,
          StrategyPalette.darkSurfaceStrong,
        ]) {
          final ratio = StrategyPalette.contrastRatio(tone, background);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${entry.key} tone $tone on $background gives '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    }

    testWidgets('the three tiers stay distinguishable', (tester) async {
      final theme = buildAppTheme();
      final top = await toneFor(tester, theme, 0.9);
      final middle = await toneFor(tester, theme, 0.5);
      final bottom = await toneFor(tester, theme, 0.1);
      expect(<Color>{top, middle, bottom}.length, 3);
    });
  });
}
