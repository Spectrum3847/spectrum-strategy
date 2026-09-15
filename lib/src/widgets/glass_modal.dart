import 'package:flutter/material.dart';

import '../theme/strategy_palette.dart';
import '../ui/glass_chrome.dart';
import 'glass_panel.dart';

Future<T?> showGlassModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool showDragHandle = false,
}) {
  if (!GlassChrome.isEnabled(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      builder: builder,
    );
  }

  final brightness = Theme.of(context).brightness;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,

    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(StrategyPalette.radiusGlassPanel),
      ),
    ),
    builder: (sheetContext) => GlassPanel(
      brightness: brightness,
      child: showDragHandle
          ? _HandleAndChild(child: builder(sheetContext))
          : builder(sheetContext),
    ),
  );
}

class _HandleAndChild extends StatelessWidget {
  const _HandleAndChild({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        Flexible(child: child),
      ],
    );
  }
}

class GlassAlertDialogShell extends StatelessWidget {
  const GlassAlertDialogShell({
    super.key,
    required this.glass,
    required this.title,
    required this.content,
    required this.actions,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final bool glass;
  final String title;
  final Widget content;
  final List<Widget> actions;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    if (!glass) {
      return AlertDialog(
        title: Text(title),
        contentPadding: contentPadding,
        content: content,
        actions: actions,
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusGlassPanel),
        ),
      ),
      child: GlassPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: contentPadding,
                child: content,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showGlassConfirmDialog<T>({
  required BuildContext context,
  required String title,

  Widget? content,

  required List<Widget> Function(BuildContext dialogContext) actionsBuilder,
  bool barrierDismissible = true,
}) {
  if (!GlassChrome.isEnabled(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: content,
        actions: actionsBuilder(dialogContext),
      ),
    );
  }

  final brightness = Theme.of(context).brightness;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusGlassPanel),
        ),
      ),
      child: GlassPanel(
        brightness: brightness,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                if (content != null) ...[const SizedBox(height: 16), content],
                const SizedBox(height: 16),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: actionsBuilder(dialogContext),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
