import 'package:flutter/material.dart';

import '../../models/strategy_point.dart';
import '../../models/strategy_stroke.dart';
import '../../widgets/field_backdrop.dart';
import '../../widgets/field_canvas_semantics.dart';
import '../../widgets/strategy_field_painter.dart';
import '../state/scout_drawing_controller.dart';
import '../../theme/strategy_palette.dart';

const double _kDefaultFieldAspectRatio = 2.0;

class ScoutDrawingCanvas extends StatefulWidget {
  const ScoutDrawingCanvas({
    required this.controller,
    this.fieldAspectRatio = _kDefaultFieldAspectRatio,
    this.backgroundImageAsset,
    this.readOnly = false,
    super.key,
  });

  final ScoutDrawingController controller;
  final double fieldAspectRatio;
  final String? backgroundImageAsset;
  final bool readOnly;

  @override
  State<ScoutDrawingCanvas> createState() => _ScoutDrawingCanvasState();
}

class _ScoutDrawingCanvasState extends State<ScoutDrawingCanvas> {
  @override
  Widget build(BuildContext context) {
    if (widget.backgroundImageAsset != null) {
      return _buildCanvas(widget.backgroundImageAsset, widget.fieldAspectRatio);
    }
    return FieldBackdrop(
      builder: (context, imageAsset, aspectRatio) =>
          _buildCanvas(imageAsset, aspectRatio),
    );
  }

  Widget _buildCanvas(String? imageAsset, double fieldAspectRatio) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final safeRatio = fieldAspectRatio <= 0
                ? _kDefaultFieldAspectRatio
                : fieldAspectRatio;
            final size = Size(width, width / safeRatio);
            final strokes = widget.controller.strokesFor(
              widget.controller.selectedPhase,
            );

            return SizedBox(
              width: size.width,
              height: size.height,
              child: Semantics(
                container: true,
                label: fieldCanvasLabel(
                  surface: 'Scouting drawing',
                  phase: widget.controller.selectedPhase,
                  strokeCount: strokes.length,
                  readOnly: widget.readOnly,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: widget.readOnly
                      ? null
                      : (details) {
                          final tool = widget.controller.selectedTool;
                          if (tool == StrategyTool.delete) {
                            widget.controller.eraseAt(
                              details.localPosition,
                              size,
                            );
                          }
                        },
                  onPanStart: widget.readOnly
                      ? null
                      : (details) {
                          final tool = widget.controller.selectedTool;
                          if (tool == StrategyTool.draw) {
                            final point = _toPoint(details.localPosition, size);
                            widget.controller.startStroke(point);
                          }
                        },
                  onPanUpdate: widget.readOnly
                      ? null
                      : (details) {
                          final tool = widget.controller.selectedTool;
                          if (tool == StrategyTool.delete) {
                            widget.controller.eraseAt(
                              details.localPosition,
                              size,
                            );
                          } else {
                            final point = _toPoint(details.localPosition, size);
                            widget.controller.extendStroke(point);
                          }
                        },
                  onPanEnd: widget.readOnly
                      ? null
                      : (details) {
                          widget.controller.finishStroke();
                        },
                  onPanCancel: widget.readOnly
                      ? null
                      : () {
                          widget.controller.finishStroke();
                        },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageAsset != null)
                        Positioned.fill(
                          child: Image.asset(imageAsset, fit: BoxFit.fill),
                        ),
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: StrategyFieldPainter(
                            strokes: strokes,
                            hasBackgroundImage: imageAsset != null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  StrategyPoint _toPoint(Offset offset, Size size) {
    final bounded = Offset(
      offset.dx.clamp(0.0, size.width),
      offset.dy.clamp(0.0, size.height),
    );
    return StrategyPoint.fromOffset(bounded, size);
  }
}

class ReadOnlyDrawingPreview extends StatefulWidget {
  const ReadOnlyDrawingPreview({required this.strokesByPhase, super.key});

  final Map<String, dynamic>? strokesByPhase;

  @override
  State<ReadOnlyDrawingPreview> createState() => _ReadOnlyDrawingPreviewState();
}

class _ReadOnlyDrawingPreviewState extends State<ReadOnlyDrawingPreview> {
  StrategyPhase _selectedPhase = StrategyPhase.auton;

  List<StrategyPhase> get _availablePhases {
    if (widget.strokesByPhase == null) return [];
    return StrategyPhase.values.where((p) {
      final list = widget.strokesByPhase![p.name];
      return list is List && list.isNotEmpty;
    }).toList();
  }

  List<StrategyStroke> _strokesFor(StrategyPhase phase) {
    final raw = widget.strokesByPhase?[phase.name];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) {
          try {
            return StrategyStroke.fromJson(m.cast<String, dynamic>());
          } catch (_) {
            return null;
          }
        })
        .whereType<StrategyStroke>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final phases = _availablePhases;
    if (phases.isEmpty) return const SizedBox.shrink();
    if (!phases.contains(_selectedPhase)) {
      _selectedPhase = phases.first;
    }
    final strokes = _strokesFor(_selectedPhase);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          children: phases
              .map(
                (p) => ChoiceChip(
                  label: Text(p.label, style: const TextStyle(fontSize: 12)),
                  selected: _selectedPhase == p,
                  selectedColor: StrategyPalette.phaseColor(p)
                      .withValues(alpha: 0.8),
                  visualDensity: VisualDensity.compact,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedPhase = p);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: FieldStrokePreview(
            strokes: strokes,
            semanticsLabel: fieldCanvasLabel(
              surface: 'Scouting drawing',
              phase: _selectedPhase,
              strokeCount: strokes.length,
              readOnly: true,
            ),
          ),
        ),
      ],
    );
  }
}

class FieldStrokePreview extends StatelessWidget {
  const FieldStrokePreview({
    required this.strokes,
    this.semanticsLabel,
    super.key,
  });

  final List<StrategyStroke> strokes;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return FieldBackdrop(
      builder: (context, imageAsset, aspectRatio) {
        final safeRatio = aspectRatio <= 0
            ? _kDefaultFieldAspectRatio
            : aspectRatio;
        return Semantics(
          container: true,
          label: semanticsLabel,
          child: AspectRatio(
            aspectRatio: safeRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageAsset != null)
                  Positioned.fill(
                    child: Image.asset(imageAsset, fit: BoxFit.fill),
                  ),
                CustomPaint(
                  painter: StrategyFieldPainter(
                    strokes: strokes,
                    hasBackgroundImage: imageAsset != null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
