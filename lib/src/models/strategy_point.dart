import 'dart:ui';

class StrategyPoint {
  const StrategyPoint(this.x, this.y);

  final double x;
  final double y;

  Offset toOffset(Size size) {
    return Offset(x * size.width, y * size.height);
  }

  factory StrategyPoint.fromOffset(Offset offset, Size size) {
    if (size.width == 0 || size.height == 0) {
      return const StrategyPoint(0, 0);
    }
    return StrategyPoint(offset.dx / size.width, offset.dy / size.height);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'x': x, 'y': y};
  }

  factory StrategyPoint.fromJson(Map<String, dynamic> json) {
    return StrategyPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }
}
