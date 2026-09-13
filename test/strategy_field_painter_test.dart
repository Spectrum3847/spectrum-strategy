import 'dart:math' as math;

import 'package:flutter/material.dart' show Color, HSLColor, Offset;
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/widgets/strategy_field_painter.dart';

void main() {
  double lightnessAt(double t) => HSLColor.fromColor(
    StrategyFieldPainter.directionColorAt(StrategyPalette.auton, t),
  ).lightness;

  test('the ramp starts on the base colour', () {
    expect(
      StrategyFieldPainter.directionColorAt(StrategyPalette.auton, 0),
      StrategyPalette.auton,
    );
  });

  test('the ramp only ever gets lighter along the line', () {
    var previous = -1.0;
    for (var i = 0; i <= 10; i++) {
      final lightness = lightnessAt(i / 10);
      expect(
        lightness,
        greaterThan(previous),
        reason: 'lightness must rise monotonically, stalled at t=${i / 10}',
      );
      previous = lightness;
    }
  });

  test('the ends are far enough apart to read at a glance', () {
    expect(lightnessAt(1) - lightnessAt(0), greaterThan(0.3));
  });

  test('the pale end still reads against a light field image', () {
    expect(lightnessAt(1), lessThan(0.8));
  });

  test('t outside 0..1 is clamped rather than overshooting', () {
    expect(lightnessAt(-1), lightnessAt(0));
    expect(lightnessAt(2), lightnessAt(1));
  });

  group('arrow direction', () {
    for (final degrees in <double>[0, 45, 90, 135, 180, 225, 270, 315]) {
      test('legs trail the apex travelling at $degrees degrees', () {
        final angle = degrees * math.pi / 180;
        final travel = Offset(math.cos(angle), math.sin(angle));
        final legs = StrategyFieldPainter.arrowLegsFor(angle);

        double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

        expect(
          dot(legs.left, travel),
          lessThan(0),
          reason: 'left leg points along travel, so the arrow is reversed',
        );
        expect(
          dot(legs.right, travel),
          lessThan(0),
          reason: 'right leg points along travel, so the arrow is reversed',
        );
      });
    }

    test('the two legs are distinct and symmetric about travel', () {
      final legs = StrategyFieldPainter.arrowLegsFor(0);

      expect(legs.left.dx, lessThan(0));
      expect(legs.right.dx, lessThan(0));
      expect(legs.left.dy, closeTo(-legs.right.dy, 1e-9));
      expect(legs.left.dy, isNot(closeTo(0, 1e-6)));
    });
  });

  test('a light base cannot ramp past the visible ceiling', () {
    const nearWhite = Color(0xFFF2EDF7);
    final ramped = HSLColor.fromColor(
      StrategyFieldPainter.directionColorAt(nearWhite, 1),
    ).lightness;
    expect(ramped, lessThanOrEqualTo(0.8));
  });
}
