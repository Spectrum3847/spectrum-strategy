import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

class DesktopLauncherService {
  DesktopLauncherService({
    String? Function()? appImagePathLoader,
    String? Function()? appDirLoader,
    String? Function()? homeLoader,
  }) : _appImagePath = appImagePathLoader ?? _defaultAppImagePath,
       _appDir = appDirLoader ?? _defaultAppDir,
       _home = homeLoader ?? _defaultHome;

  final String? Function() _appImagePath;
  final String? Function() _appDir;
  final String? Function() _home;

  bool get isSupported =>
      !kIsWeb && Platform.isLinux && (_appImagePath()?.isNotEmpty ?? false);

  Future<String> registerInLauncher() async {
    final appImage = _appImagePath();
    final home = _home();
    if (appImage == null || appImage.isEmpty || home == null || home.isEmpty) {
      throw StateError('Launcher registration needs a Linux AppImage');
    }
    final iconPath = await _installIcon(home);
    final appsDir = Directory('$home/.local/share/applications');
    await appsDir.create(recursive: true);
    final file = File('${appsDir.path}/spectrumstrategy.desktop');
    await file.writeAsString(desktopEntry(appImage, iconPath: iconPath));
    return file.path;
  }

  Future<String?> _installIcon(String home) async {
    final appDir = _appDir();
    if (appDir == null || appDir.isEmpty) return null;
    final source = File('$appDir/spectrumstrategy.png');

    if (!await source.exists() || await source.length() < 64) return null;
    final iconsDir = Directory('$home/.local/share/icons');
    await iconsDir.create(recursive: true);
    final dest = '${iconsDir.path}/spectrumstrategy.png';
    await source.copy(dest);
    return dest;
  }

  static String desktopEntry(String appImagePath, {String? iconPath}) {
    final exec = appImagePath.replaceAllMapped(RegExp(r'[%"`$\\]'), (m) {
      final char = m[0]!;
      if (char == '%') return '%%';
      if (char == r'\') return r'\\\\';
      return '\\\\$char';
    });
    final icon = (iconPath ?? 'spectrumstrategy')
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n');
    return '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Spectrum Strategy\n'
        'Exec="$exec" %U\n'
        'Icon=$icon\n'
        'Categories=Utility;\n'
        'Terminal=false\n';
  }

  static String? _defaultAppImagePath() => Platform.environment['APPIMAGE'];
  static String? _defaultAppDir() => Platform.environment['APPDIR'];
  static String? _defaultHome() => Platform.environment['HOME'];
}
