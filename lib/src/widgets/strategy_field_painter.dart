import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/strategy_stroke.dart';
import '../theme/strategy_palette.dart';

const double _directionLightnessRange = 0.42;
const double _maxStrokeLightness = 0.78;

const double _strokeWidth = 4;

const double _arrowSpacing = 56;
const double _arrowLength = 7;
const double _arrowStrokeWidth = 2.5;

const double _arrowHalfAngle = 0.45;

class StrategyFieldPainter extends CustomPainter {
  StrategyFieldPainter({required this.strokes, this.hasBackgroundImage = false})
    : _totalPoints = strokes.fold<int>(0, (sum, s) => sum + s.points.length);

  final List<StrategyStroke> strokes;
  final bool hasBackgroundImage;
  final int _totalPoints;

  @override
  void paint(Canvas canvas, Size size) {
    if (!hasBackgroundImage) {
      final background = Paint()..color = StrategyPalette.surface;
      canvas.drawRect(Offset.zero & size, background);
    }

    final borderPaint = Paint()
      ..color = StrategyPalette.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, borderPaint);

    final gridPaint = Paint()
      ..color = StrategyPalette.grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final dx = size.width * index / 4;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }
    for (var index = 1; index < 4; index++) {
      final dy = size.height * index / 4;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    final centerPaint = Paint()
      ..color = StrategyPalette.primary.withValues(alpha: 0.2)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );

    for (final stroke in strokes) {
      _paintStroke(canvas, size, stroke);
    }
  }

  void _paintStroke(Canvas canvas, Size size, StrategyStroke stroke) {
    if (stroke.points.length < 2) return;

    final points = stroke.points
        .map((point) => point.toOffset(size))
        .toList(growable: false);

    final segmentLengths = <double>[];
    var totalLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      final length = (points[i] - points[i - 1]).distance;
      segmentLengths.add(length);
      totalLength += length;
    }
    if (totalLength <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = _strokeWidth;

    var travelled = 0.0;
    var nextArrowAt = _arrowSpacing;
    for (var i = 1; i < points.length; i++) {
      final segment = segmentLengths[i - 1];
      final midpoint = travelled + segment / 2;
      final t = (midpoint / totalLength).clamp(0.0, 1.0);
      final colour = directionColorAt(stroke.color, t);

      paint.color = colour.withValues(alpha: 0.95);
      canvas.drawLine(points[i - 1], points[i], paint);

      travelled += segment;

      while (travelled >= nextArrowAt &&
          totalLength - nextArrowAt > _arrowSpacing / 2) {
        _paintArrow(canvas, points[i - 1], points[i], colour);
        nextArrowAt += _arrowSpacing;
      }
    }
  }

  static Color directionColorAt(Color base, double t) {
    final hsl = HSLColor.fromColor(base);
    final end = (hsl.lightness + _directionLightnessRange).clamp(
      0.0,
      _maxStrokeLightness,
    );
    final clamped = t.clamp(0.0, 1.0);
    return hsl
        .withLightness(hsl.lightness + (end - hsl.lightness) * clamped)
        .toColor();
  }

  void _paintArrow(Canvas canvas, Offset from, Offset to, Color colour) {
    final direction = to - from;
    if (direction.distance == 0) return;
    final angle = direction.direction;

    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = _arrowStrokeWidth;

    final left = Offset(
      to.dx - _arrowLength * math.cos(angle - _arrowHalfAngle),
      to.dy - _arrowLength * math.sin(angle - _arrowHalfAngle),
    );
    final right = Offset(
      to.dx - _arrowLength * math.cos(angle + _arrowHalfAngle),
      to.dy - _arrowLength * math.sin(angle + _arrowHalfAngle),
    );
    canvas.drawLine(left, to, paint);
    canvas.drawLine(right, to, paint);
  }

  static ({Offset left, Offset right}) arrowLegsFor(double angle) => (
    left: Offset(
      -math.cos(angle - _arrowHalfAngle),
      -math.sin(angle - _arrowHalfAngle),
    ),
    right: Offset(
      -math.cos(angle + _arrowHalfAngle),
      -math.sin(angle + _arrowHalfAngle),
    ),
  );

  @override
  bool shouldRepaint(covariant StrategyFieldPainter oldDelegate) {
    return strokes.length != oldDelegate.strokes.length ||
        _totalPoints != oldDelegate._totalPoints ||
        hasBackgroundImage != oldDelegate.hasBackgroundImage;
  }
}
