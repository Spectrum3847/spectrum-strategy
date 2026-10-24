import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:liquid_glass/liquid_glass.dart';

import '../theme/strategy_palette.dart';
import '../ui/glass_chrome.dart';

class GlassPopupMenuButton<T> extends StatelessWidget {
  const GlassPopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.onCanceled,
    this.initialValue,
    this.tooltip,
    this.icon,
    this.child,
    this.enabled = true,
  }) : assert(icon == null || child == null);

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onCanceled;
  final T? initialValue;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!GlassChrome.isEnabled(context)) {
      return PopupMenuButton<T>(
        itemBuilder: itemBuilder,
        onSelected: onSelected,
        onCanceled: onCanceled,
        initialValue: initialValue,
        tooltip: tooltip,
        icon: icon,
        enabled: enabled,
        child: child,
      );
    }
    return _GlassMenuButton<T>(
      itemBuilder: itemBuilder,
      onSelected: onSelected,
      onCanceled: onCanceled,
      initialValue: initialValue,
      tooltip: tooltip,
      icon: icon,
      enabled: enabled,
      child: child,
    );
  }
}

class _GlassMenuButton<T> extends StatefulWidget {
  const _GlassMenuButton({
    required this.itemBuilder,
    required this.onSelected,
    required this.onCanceled,
    required this.initialValue,
    required this.tooltip,
    required this.icon,
    required this.child,
    required this.enabled,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final VoidCallback? onCanceled;
  final T? initialValue;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final bool enabled;

  @override
  State<_GlassMenuButton<T>> createState() => _GlassMenuButtonState<T>();
}

class _GlassMenuButtonState<T> extends State<_GlassMenuButton<T>> {
  Future<void> _open() async {
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final anchor = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );

    final brightness = Theme.of(context).brightness;
    final value = await Navigator.of(context).push(
      _GlassPopupMenuRoute<T>(
        anchor: anchor,
        items: items,
        initialValue: widget.initialValue,
        brightness: brightness,
        barrierLabel: MaterialLocalizations.of(context).menuDismissLabel,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Navigator.of(context).context,
        ),
      ),
    );
    if (!mounted) return;

    if (value == null) {
      widget.onCanceled?.call();
    } else {
      widget.onSelected?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child == null) {
      return IconButton(
        icon: widget.icon ?? Icon(Icons.adaptive.more),
        tooltip: widget.tooltip,
        onPressed: widget.enabled ? _open : null,
      );
    }
    final button = InkWell(
      onTap: widget.enabled ? _open : null,
      borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      child: child,
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

class _GlassPopupMenuRoute<T> extends PopupRoute<T> {
  _GlassPopupMenuRoute({
    required this.anchor,
    required this.items,
    required this.initialValue,
    required this.brightness,
    required this.barrierLabel,
    required this.capturedThemes,
  });

  final Rect anchor;
  final List<PopupMenuEntry<T>> items;
  final T? initialValue;

  final Brightness brightness;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
    );

    Widget menu = Material(
      type: MaterialType.transparency,
      child: LiquidGlass(
        key: ValueKey(brightness),
        cornerRadius: StrategyPalette.radiusGlassPanel,
        brightness: brightness,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(StrategyPalette.radiusGlassPanel),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                StrategyPalette.radiusGlassPanel,
              ),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.4)),
            ),
            child: IntrinsicWidth(
              child: Semantics(
                role: SemanticsRole.menu,
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: MaterialLocalizations.of(context).popupMenuLabel,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in items)
                        if (initialValue != null &&
                            item.represents(initialValue))
                          ColoredBox(
                            color: scheme.primary.withValues(alpha: 0.1),
                            child: item,
                          )
                        else
                          item,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    menu = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
        alignment: Alignment.topCenter,
        child: menu,
      ),
    );

    return SafeArea(
      child: CustomSingleChildLayout(
        delegate: _GlassMenuLayout(
          anchor: anchor.shift(Offset(-padding.left, -padding.top)),
          textDirection: Directionality.of(context),
        ),
        child: capturedThemes.wrap(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 168, maxWidth: 320),
            child: menu,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _GlassMenuLayout extends SingleChildLayoutDelegate {
  const _GlassMenuLayout({required this.anchor, required this.textDirection});

  final Rect anchor;
  final TextDirection textDirection;

  static const double _edge = 8;
  static const double _gap = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(constraints.maxWidth - _edge * 2, constraints.maxHeight - _edge * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = textDirection == TextDirection.rtl
        ? anchor.left
        : anchor.right - childSize.width;
    final maxX = math.max(_edge, size.width - childSize.width - _edge);

    var y = anchor.bottom + _gap;
    if (y + childSize.height > size.height - _edge) {
      y = anchor.top - _gap - childSize.height;
    }
    final maxY = math.max(_edge, size.height - childSize.height - _edge);
    return Offset(clampDouble(x, _edge, maxX), clampDouble(y, _edge, maxY));
  }

  @override
  bool shouldRelayout(_GlassMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      textDirection != oldDelegate.textDirection;
}
