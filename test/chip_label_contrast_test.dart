import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<Color> _paintedLabelColour(
  WidgetTester tester,
  ThemeData theme, {
  required bool selected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: FilterChip(
          selected: selected,
          onSelected: (_) {},
          label: const Text('chip'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final paragraph = tester.renderObject<RenderParagraph>(find.text('chip'));
  final colour = paragraph.text.style?.color;
  expect(colour, isNotNull, reason: 'the chip label must paint a colour');
  return colour!;
}

void main() {
  group('selected chip label clears WCAG AA on the selected fill', () {
    testWidgets('light', (tester) async {
      final colour = await _paintedLabelColour(
        tester,
        buildAppTheme(),
        selected: true,
      );
      expect(colour, Colors.white);
      expect(_contrast(colour, StrategyPalette.primary), greaterThan(4.5));
    });

    testWidgets('dark', (tester) async {
      final colour = await _paintedLabelColour(
        tester,
        buildDarkAppTheme(),
        selected: true,
      );
      expect(colour, StrategyPalette.darkOnPrimary);
      expect(_contrast(colour, StrategyPalette.darkPrimary), greaterThan(4.5));
    });
  });

  group('an unselected chip label is unchanged', () {
    testWidgets('light', (tester) async {
      expect(
        await _paintedLabelColour(tester, buildAppTheme(), selected: false),
        StrategyPalette.textPrimary,
      );
    });

    testWidgets('dark', (tester) async {
      expect(
        await _paintedLabelColour(tester, buildDarkAppTheme(), selected: false),
        StrategyPalette.darkText,
      );
    });
  });
}
