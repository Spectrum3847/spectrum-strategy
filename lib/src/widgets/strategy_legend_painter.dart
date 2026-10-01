import 'package:flutter/material.dart';

import '../models/strategy_stroke.dart';

class StrategyLegendPainter extends CustomPainter {
  StrategyLegendPainter({
    required this.strokes,
    required this.ink,
    required this.background,
  }) : _pointCount = strokes.fold<int>(
         0,
         (n, stroke) => n + stroke.points.length,
       );

  final List<StrategyStroke> strokes;
  final Color ink;
  final Color background;
  final int _pointCount;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final slot = size.width / 3;
    final symbol = (slot * 0.22).clamp(12.0, 30.0);
    for (var i = 0; i < 3; i++) {
      final left = slot * i + 4;
      final top = (size.height - symbol) / 2;
      final rect = Rect.fromLTWH(left, top, symbol, symbol);
      switch (i) {
        case 0:
          canvas.drawPath(
            Path()
              ..moveTo(rect.center.dx, rect.top)
              ..lineTo(rect.right, rect.bottom)
              ..lineTo(rect.left, rect.bottom)
              ..close(),
            pen,
          );
        case 1:
          canvas.drawOval(rect, pen);
        case 2:
          canvas.drawRect(rect, pen);
      }
      canvas.drawLine(
        Offset(rect.right + 8, size.height - 8),
        Offset(slot * (i + 1) - 8, size.height - 8),
        pen,
      );
    }
    pen.strokeWidth = 3;
    for (final stroke in strokes.where((stroke) => stroke.isLegend)) {
      if (stroke.points.isEmpty) continue;
      final points = stroke.points
          .map((point) => point.toOffset(size))
          .toList();
      if (points.length == 1) {
        canvas.drawCircle(points.first, 1.5, Paint()..color = ink);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, pen);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StrategyLegendPainter oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.background != background ||
      oldDelegate._pointCount != _pointCount ||
      oldDelegate.strokes != strokes;
}
