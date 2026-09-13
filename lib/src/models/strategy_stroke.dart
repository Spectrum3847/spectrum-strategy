import 'package:flutter/material.dart';

import '../theme/strategy_palette.dart';
import 'strategy_point.dart';

class StrategyStroke {
  StrategyStroke({
    required this.phase,
    List<StrategyPoint>? points,
    int? colorValue,
  }) : points = points ?? <StrategyPoint>[],
       colorValue = colorValue ?? StrategyPalette.phaseColor(phase).toARGB32();

  final StrategyPhase phase;
  final List<StrategyPoint> points;
  final int colorValue;

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'phase': phase.name,
      'colorValue': colorValue,
      'points': points.map((point) => point.toJson()).toList(),
    };
  }

  factory StrategyStroke.fromJson(Map<String, dynamic> json) {
    final phase =
        strategyPhaseByNameOrNull(json['phase']) ?? StrategyPhase.auton;
    final points = <StrategyPoint>[];
    final rawPoints = json['points'];
    if (rawPoints is List) {
      for (final value in rawPoints) {
        if (value is! Map) {
          continue;
        }
        try {
          points.add(StrategyPoint.fromJson(value.cast<String, dynamic>()));
        } catch (_) {}
      }
    }
    final colorValue = json['colorValue'];
    return StrategyStroke(
      phase: phase,
      colorValue: colorValue is num ? colorValue.toInt() : null,
      points: points,
    );
  }
}
