import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

class DebugInfo {
  const DebugInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.osVersion,
    required this.device,
    required this.gitCommit,
    required this.gitBranch,
    required this.buildDate,
  });

  final String appVersion;

  final String buildNumber;

  final String platform;

  final String osVersion;

  final String device;

  final String gitCommit;

  final String gitBranch;

  final String buildDate;

  static const String _envCommit = String.fromEnvironment('GIT_COMMIT');
  static const String _envBranch = String.fromEnvironment('GIT_BRANCH');
  static const String _envBuildDate = String.fromEnvironment('BUILD_DATE');

  String get versionLabel =>
      buildNumber.isEmpty ? appVersion : '$appVersion+$buildNumber';

  String get commitLabel => gitCommit.isEmpty ? 'local build' : gitCommit;

  String get reportVersion {
    final parts = <String>[
      commitLabel,
      if (gitBranch.isNotEmpty) gitBranch,
      if (buildDate.isNotEmpty) buildDate,
    ];
    return '$versionLabel (${parts.join(' ')})';
  }

  String toDisplayText() {
    final lines = <String>[
      'App version: $versionLabel',
      'Commit: $commitLabel',
      if (gitBranch.isNotEmpty) 'Branch: $gitBranch',
      if (buildDate.isNotEmpty) 'Built: $buildDate',
      'Platform: $platform',
      if (osVersion.isNotEmpty) 'OS: $osVersion',
      if (device.isNotEmpty) 'Device: $device',
    ];
    return lines.join('\n');
  }

  static Future<DebugInfo> gather() async {
    var version = 'unknown';
    var build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}
    return DebugInfo(
      appVersion: version,
      buildNumber: build,
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      osVersion: kIsWeb ? '' : Platform.operatingSystemVersion,
      device: await _deviceSummary(),
      gitCommit: _envCommit,
      gitBranch: _envBranch,
      buildDate: _envBuildDate,
    );
  }

  static Future<String> _deviceSummary() async {
    if (kIsWeb) return 'web';
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final d = await plugin.androidInfo;
        return '${d.manufacturer} ${d.model} (Android ${d.version.release}, '
            'SDK ${d.version.sdkInt})';
      }
      if (Platform.isIOS) {
        final d = await plugin.iosInfo;
        return '${d.name} ${d.model} (iOS ${d.systemVersion})';
      }
      if (Platform.isMacOS) {
        final d = await plugin.macOsInfo;
        return '${d.model} (macOS ${d.osRelease})';
      }
      if (Platform.isWindows) {
        final d = await plugin.windowsInfo;
        return '${d.productName} (${d.displayVersion})';
      }
      if (Platform.isLinux) {
        final d = await plugin.linuxInfo;
        return d.prettyName;
      }
    } catch (_) {}
    return '';
  }
}
