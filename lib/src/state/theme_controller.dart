import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'app_theme_mode';
const _kLiquidGlassKey = 'app_liquid_glass';

bool _platformDefaultLiquidGlass() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class ThemeController extends ChangeNotifier {
  ThemeController({bool? liquidGlassDefault})
    : _liquidGlassDefault = liquidGlassDefault ?? _platformDefaultLiquidGlass();

  final bool _liquidGlassDefault;

  Future<void>? _bootstrapFuture;
  ThemeMode _themeMode = ThemeMode.system;
  late bool _liquidGlass = _liquidGlassDefault;

  ThemeMode get themeMode => _themeMode;

  bool get liquidGlass => _liquidGlass;

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _bootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kThemeModeKey);

    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
    _liquidGlass = prefs.getBool(_kLiquidGlassKey) ?? _liquidGlassDefault;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setLiquidGlass(bool enabled) async {
    if (_liquidGlass == enabled) return;
    _liquidGlass = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLiquidGlassKey, enabled);
  }
}
