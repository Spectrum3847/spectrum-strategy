import 'package:flutter/widgets.dart';
import 'package:liquid_glass/liquid_glass.dart' show liquidGlassSupported;

import 'platform_target.dart';

const bool spectrumGlassMacosEnabled = bool.fromEnvironment(
  'SPECTRUM_GLASS_MACOS',
);

Future<bool> spectrumGlassSupported() async {
  if (isMacosPlatform && !spectrumGlassMacosEnabled) return false;
  return liquidGlassSupported();
}

class GlassChrome extends InheritedWidget {
  const GlassChrome({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool isEnabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassChrome>()?.enabled ??
      false;

  static double bottomInsetOf(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  @override
  bool updateShouldNotify(GlassChrome oldWidget) =>
      enabled != oldWidget.enabled;
}
