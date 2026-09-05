import 'package:flutter/material.dart';

import '../../models/strategy_point.dart';
import '../../models/strategy_stroke.dart';
import '../../theme/strategy_palette.dart';

class ScoutDrawingController extends ChangeNotifier {
  ScoutDrawingController();

  final Map<StrategyPhase, List<StrategyStroke>> _strokesByPhase = {
    for (final phase in StrategyPhase.values) phase: <StrategyStroke>[],
  };

  StrategyPhase _selectedPhase = StrategyPhase.auton;
  StrategyTool _selectedTool = StrategyTool.draw;

  StrategyPhase get selectedPhase => _selectedPhase;
  StrategyTool get selectedTool => _selectedTool;

  List<StrategyStroke> strokesFor(StrategyPhase phase) =>
      List.unmodifiable(_strokesByPhase[phase] ?? []);

  Map<StrategyPhase, List<StrategyStroke>> get allStrokes =>
      Map.unmodifiable(_strokesByPhase);

  bool get isEmpty {
    return _strokesByPhase.values.every((list) => list.isEmpty);
  }

  set selectedPhase(StrategyPhase phase) {
    if (phase == _selectedPhase) return;
    _selectedPhase = phase;
    notifyListeners();
  }

  set selectedTool(StrategyTool tool) {
    if (tool == _selectedTool) return;
    _selectedTool = tool;
    notifyListeners();
  }

  void startStroke(StrategyPoint point) {
    final color = StrategyPalette.phaseColor(_selectedPhase).toARGB32();
    final stroke = StrategyStroke(
      phase: _selectedPhase,
      colorValue: color,
      points: [point],
    );
    _strokesByPhase[_selectedPhase]!.add(stroke);
    notifyListeners();
  }

  void extendStroke(StrategyPoint point) {
    final strokes = _strokesByPhase[_selectedPhase];
    if (strokes == null || strokes.isEmpty) return;
    final last = strokes.last;
    if (last.points.isNotEmpty &&
        last.points.last.x == point.x &&
        last.points.last.y == point.y) {
      return;
    }
    last.points.add(point);
    notifyListeners();
  }

  void finishStroke() {}

  bool eraseAt(Offset pixelPosition, Size canvasSize) {
    final strokes = _strokesByPhase[_selectedPhase];
    if (strokes == null || strokes.isEmpty) return false;

    const radiusPx = 24.0;
    final radiusSquared = radiusPx * radiusPx;
    final tap = Offset(
      pixelPosition.dx.clamp(0.0, canvasSize.width),
      pixelPosition.dy.clamp(0.0, canvasSize.height),
    );
    var removed = false;
    strokes.removeWhere((stroke) {
      for (final p in stroke.points) {
        final pointPx = p.toOffset(canvasSize);
        final dx = pointPx.dx - tap.dx;
        final dy = pointPx.dy - tap.dy;
        if ((dx * dx + dy * dy) < radiusSquared) {
          removed = true;
          return true;
        }
      }
      return false;
    });

    if (removed) notifyListeners();
    return removed;
  }

  Map<String, dynamic> toJson() {
    final strokesJson = <String, dynamic>{};
    for (final entry in _strokesByPhase.entries) {
      if (entry.value.isNotEmpty) {
        strokesJson[entry.key.name] = entry.value
            .map((s) => s.toJson())
            .toList();
      }
    }
    return strokesJson;
  }

  void loadFromJson(Map<String, dynamic>? json) {
    for (final phase in StrategyPhase.values) {
      _strokesByPhase[phase] = <StrategyStroke>[];
    }
    if (json == null) return;
    for (final entry in json.entries) {
      final phase = strategyPhaseByNameOrNull(entry.key);
      if (phase == null) continue;
      final rawStrokes = entry.value;
      if (rawStrokes is! List) continue;
      final strokes = <StrategyStroke>[];
      for (final value in rawStrokes) {
        if (value is! Map) continue;
        try {
          strokes.add(StrategyStroke.fromJson(value.cast<String, dynamic>()));
        } catch (_) {}
      }
      _strokesByPhase[phase] = strokes;
    }
    notifyListeners();
  }

  void clear() {
    for (final phase in StrategyPhase.values) {
      _strokesByPhase[phase] = <StrategyStroke>[];
    }
    notifyListeners();
  }
}
