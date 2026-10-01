import 'package:flutter/material.dart';

import '../theme/strategy_palette.dart';

class FilmSplitView extends StatefulWidget {
  const FilmSplitView({
    required this.primary,
    required this.secondary,
    this.initialFraction = 0.55,
    this.minFraction = 0.25,
    this.sideBySideBreakpoint = 720,
    super.key,
  });

  final Widget primary;

  final Widget secondary;

  final double initialFraction;

  final double minFraction;

  final double sideBySideBreakpoint;

  @override
  State<FilmSplitView> createState() => _FilmSplitViewState();
}

class _FilmSplitViewState extends State<FilmSplitView> {
  late double _fraction = widget.initialFraction;

  static const double _handleThickness = 12;
  static const double _keyboardStep = 0.05;

  void _moveBy(double delta, double extent) {
    if (extent <= 0) return;
    setState(() {
      _fraction = (_fraction + delta / extent).clamp(
        widget.minFraction,
        1 - widget.minFraction,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= widget.sideBySideBreakpoint;
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        if (!extent.isFinite || extent <= 0) {
          return widget.primary;
        }

        final available = extent - _handleThickness;
        final primaryExtent = (available * _fraction).clamp(
          available * widget.minFraction,
          available * (1 - widget.minFraction),
        );

        final children = <Widget>[
          SizedBox(
            width: horizontal ? primaryExtent : null,
            height: horizontal ? null : primaryExtent,
            child: widget.primary,
          ),
          _SplitHandle(
            horizontal: horizontal,
            thickness: _handleThickness,
            onDrag: (delta) => _moveBy(delta, available),
            onStep: (forward) => _moveBy(
              (forward ? 1 : -1) * _keyboardStep * available,
              available,
            ),
          ),
          Expanded(child: widget.secondary),
        ];

        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({
    required this.horizontal,
    required this.thickness,
    required this.onDrag,
    required this.onStep,
  });

  final bool horizontal;
  final double thickness;
  final ValueChanged<double> onDrag;
  final ValueChanged<bool> onStep;

  @override
  Widget build(BuildContext context) {
    final bar = Center(
      child: Container(
        width: horizontal ? 2 : 40,
        height: horizontal ? 40 : 2,
        decoration: BoxDecoration(
          color: StrategyPalette.borderOf(context),
          borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        ),
      ),
    );

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: Semantics(
        slider: true,
        label: 'Resize the film and form panes',
        onIncrease: () => onStep(true),
        onDecrease: () => onStep(false),
        child: GestureDetector(
          key: const ValueKey('film-split-handle'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: horizontal ? (d) => onDrag(d.delta.dx) : null,
          onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
          child: SizedBox(
            width: horizontal ? thickness : null,
            height: horizontal ? null : thickness,
            child: bar,
          ),
        ),
      ),
    );
  }
}
