import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../models/robot_marker.dart';
import '../models/strategy_point.dart';
import '../models/strategy_session.dart';
import '../services/team_avatar_service.dart';
import '../state/strategy_controller.dart';
import '../theme/strategy_palette.dart';
import 'field_canvas_semantics.dart';
import 'strategy_field_painter.dart';
import 'strategy_legend_painter.dart';

const double _kDefaultFieldAspectRatio = 2.0;
const double _kMarkerSize = 36.0;
const double _kMarkerHalfSize = _kMarkerSize / 2;

class StrategyFieldCanvas extends StatefulWidget {
  const StrategyFieldCanvas({
    required this.controller,
    required this.repaintKey,
    required this.fieldAspectRatio,
    this.backgroundImageAsset,
    this.showLegend = false,
    this.onElementErased,
    this.teamAvatarService,
    super.key,
  });

  final StrategyController controller;
  final GlobalKey repaintKey;
  final String? backgroundImageAsset;
  final bool showLegend;
  final double fieldAspectRatio;

  final void Function(StrategySession snapshot)? onElementErased;

  final TeamAvatarService? teamAvatarService;

  @override
  State<StrategyFieldCanvas> createState() => _StrategyFieldCanvasState();
}

class _StrategyFieldCanvasState extends State<StrategyFieldCanvas> {
  StrategySession? _preEraseSnapshot;
  bool _erasedDuringGesture = false;

  int? _activePointerId;
  bool _gestureInLegend = false;
  static const double _legendHeight = 64;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final legendHeight = widget.showLegend ? _legendHeight : 0.0;
            final safeAspectRatio = widget.fieldAspectRatio <= 0
                ? _kDefaultFieldAspectRatio
                : widget.fieldAspectRatio;

            final maxFieldHeight = widget.showLegend
                ? (constraints.maxHeight - legendHeight).clamp(
                    0.0,
                    double.infinity,
                  )
                : double.infinity;
            final width = maxFieldHeight.isFinite
                ? constraints.maxWidth.clamp(
                    0.0,
                    maxFieldHeight * safeAspectRatio,
                  )
                : constraints.maxWidth;
            final size = Size(width, width / safeAspectRatio);
            final phase = widget.controller.session.selectedPhase;
            final strokes = widget.controller.session.strokesFor(phase);
            return Align(
              alignment: Alignment.topCenter,
              widthFactor: 1,
              heightFactor: 1,
              child: SizedBox(
                width: size.width,
                height: size.height + legendHeight,
                child: RepaintBoundary(
                  key: widget.repaintKey,
                  child: Column(
                    children: [
                      if (widget.showLegend)
                        Semantics(
                          label: 'Opponent team numbers: triangle, circle, square. Draw numbers beside each shape.',
                          child: Listener(
                            key: const ValueKey('strategy-team-legend'),
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) => _onPointerDown(
                              event,
                              Size(width, legendHeight),
                              isLegend: true,
                            ),
                            onPointerMove: (event) => _onPointerMove(
                              event,
                              Size(width, legendHeight),
                            ),
                            onPointerUp: _onPointerUp,
                            onPointerCancel: _onPointerCancel,
                            child: ClipRect(
                              child: CustomPaint(
                                size: Size(width, legendHeight),
                                painter: StrategyLegendPainter(
                                  strokes: strokes,
                                  ink: Theme.of(context).colorScheme.onSurface,
                                  background: Theme.of(context)
                                      .colorScheme
                                      .surface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: size.width,
                        height: size.height,
                        child: Semantics(
                          container: true,
                          label: fieldCanvasLabel(
                            surface: 'Strategy board',
                            phase: phase,
                            strokeCount: strokes.length,
                            markerCount: widget.controller.session
                                .markersFor(phase)
                                .length,
                          ),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) =>
                                _onPointerDown(event, size),
                            onPointerMove: (event) =>
                                _onPointerMove(event, size),
                            onPointerUp: _onPointerUp,
                            onPointerCancel: _onPointerCancel,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (widget.backgroundImageAsset != null)
                                  Positioned.fill(
                                    child: Image.asset(
                                      widget.backgroundImageAsset!,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                RepaintBoundary(
                                  child: CustomPaint(
                                    painter: StrategyFieldPainter(
                                      strokes: strokes,
                                      hasBackgroundImage:
                                          widget.backgroundImageAsset != null,
                                    ),
                                  ),
                                ),
                                ..._buildMarkerWidgets(size, phase),
                              ],
                            ),
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

  static const _acceptedPointerKinds = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.mouse,
  };

  void _onPointerDown(
    PointerDownEvent event,
    Size size, {
    bool isLegend = false,
  }) {
    if (!_acceptedPointerKinds.contains(event.kind)) {
      return;
    }

    if (_activePointerId != null) {
      return;
    }
    final tool = widget.controller.session.selectedTool;
    if (isLegend && tool == StrategyTool.robot) return;
    _activePointerId = event.pointer;
    _gestureInLegend = isLegend;
    if (tool == StrategyTool.robot) {
      if (!widget.controller.startMarkerDragAt(event.localPosition, size)) {
        widget.controller.placeRobot(_toPoint(event.localPosition, size));
      }
    } else if (tool == StrategyTool.delete) {
      _preEraseSnapshot = widget.controller.captureSnapshot();
      _erasedDuringGesture = false;
      if (widget.controller.eraseAt(
        event.localPosition,
        size,
        isLegend: _gestureInLegend,
      )) {
        _erasedDuringGesture = true;
      }
    } else {
      widget.controller.startStroke(
        _toPoint(event.localPosition, size),
        isLegend: isLegend,
      );
    }
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _activePointerId) {
      return;
    }
    final tool = widget.controller.session.selectedTool;
    if (tool == StrategyTool.delete) {
      if (widget.controller.eraseAt(
        event.localPosition,
        size,
        isLegend: _gestureInLegend,
      )) {
        _erasedDuringGesture = true;
      }
    } else if (tool == StrategyTool.robot) {
      widget.controller.updateMarkerDrag(_toPoint(event.localPosition, size));
    } else {
      widget.controller.extendStroke(_toPoint(event.localPosition, size));
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) {
      return;
    }
    _activePointerId = null;
    final tool = widget.controller.session.selectedTool;
    if (tool == StrategyTool.delete) {
      if (_erasedDuringGesture) {
        widget.onElementErased?.call(_preEraseSnapshot!);
      }
      _preEraseSnapshot = null;
      _erasedDuringGesture = false;
      widget.controller.finishErase();
    } else if (tool == StrategyTool.robot) {
      widget.controller.finishMarkerDrag();
    } else {
      widget.controller.finishStroke();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) {
      return;
    }
    _activePointerId = null;
    _preEraseSnapshot = null;
    _erasedDuringGesture = false;
    widget.controller.finishErase();
    widget.controller.finishMarkerDrag();
    widget.controller.finishStroke();
  }

  List<Widget> _buildMarkerWidgets(Size size, StrategyPhase phase) {
    final markers = widget.controller.session.markersFor(phase);
    return markers
        .map((RobotMarker marker) {
          final offset = marker.position.toOffset(size);
          return Positioned(
            left: offset.dx - _kMarkerHalfSize,
            top: offset.dy - _kMarkerHalfSize,
            child: _RobotMarkerView(
              marker: marker,
              avatarService: widget.teamAvatarService,
            ),
          );
        })
        .toList(growable: false);
  }

  StrategyPoint _toPoint(Offset offset, Size size) {
    final bounded = Offset(
      offset.dx.clamp(0.0, size.width),
      offset.dy.clamp(0.0, size.height),
    );
    return StrategyPoint.fromOffset(bounded, size);
  }
}

class _RobotMarkerView extends StatefulWidget {
  const _RobotMarkerView({required this.marker, this.avatarService});

  final RobotMarker marker;
  final TeamAvatarService? avatarService;

  @override
  State<_RobotMarkerView> createState() => _RobotMarkerViewState();
}

class _RobotMarkerViewState extends State<_RobotMarkerView> {
  Uint8List? _avatar;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant _RobotMarkerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker.teamNumber != widget.marker.teamNumber) {
      _avatar = null;
      _loadAvatar();
    }
  }

  void _loadAvatar() {
    final team = widget.marker.teamNumber;
    final service = widget.avatarService;
    if (team == null || service == null) {
      return;
    }
    service.avatarFor(team).then((bytes) {
      if (mounted && bytes != null) {
        setState(() => _avatar = bytes);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allianceColor = StrategyPalette.allianceColor(widget.marker.alliance);
    final phaseColor = StrategyPalette.phaseColor(widget.marker.phase);
    final teamText = widget.marker.teamNumber?.toString();
    final radius = BorderRadius.circular(StrategyPalette.radiusSm);
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: allianceColor,
                borderRadius: radius,
                border: Border.all(color: allianceColor, width: 2),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: _avatar != null
                    ? Image.memory(
                        _avatar!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: teamText != null
                            ? Text(
                                teamText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      height: 1.0,
                                    ),
                              )
                            : const Icon(
                                Icons.smart_toy_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: phaseColor,
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
          if (teamText != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: StrategyPalette.onAlliance.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(
                      StrategyPalette.radiusSm,
                    ),
                    border: Border.all(color: allianceColor, width: 1),
                  ),
                  child: Text(
                    teamText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: allianceColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
