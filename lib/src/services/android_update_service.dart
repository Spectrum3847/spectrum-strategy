import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_update_service.dart';
import 'http_timeout_client.dart';

class AndroidUpdateInfo {
  const AndroidUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    this.apkUrl,
    this.expectedSha256,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final String? apkUrl;
  final String? expectedSha256;
}

enum AndroidInstallOutcome { installed, permissionRequired }

class AndroidUpdateCheck {
  const AndroidUpdateCheck({required this.update, required this.hasRelease})
    : supported = true;
  const AndroidUpdateCheck.notSupported()
    : update = null,
      hasRelease = false,
      supported = false;
  const AndroidUpdateCheck.noRelease()
    : update = null,
      hasRelease = false,
      supported = true;
  const AndroidUpdateCheck.upToDate()
    : update = null,
      hasRelease = true,
      supported = true;

  final AndroidUpdateInfo? update;
  final bool hasRelease;
  final bool supported;
}

class AndroidUpdateService {
  AndroidUpdateService({
    DesktopUpdateService? updateService,
    http.Client? client,
    Future<SharedPreferences> Function()? prefs,
    Future<Directory> Function()? cacheDirLoader,
    Future<AndroidInstallOutcome> Function(String path)? installer,
    bool Function()? isAndroid,
    DateTime Function()? now,
  }) : _updateService =
           updateService ?? DesktopUpdateService(assetSelector: _apkAsset),
       _client = client ?? TimeoutHttpClient(),
       _prefsLoader = prefs ?? SharedPreferences.getInstance,
       _cacheDirLoader = cacheDirLoader ?? getTemporaryDirectory,
       _installer = installer ?? _defaultInstaller,
       _isAndroid = isAndroid ?? _defaultIsAndroid,
       _now = now ?? DateTime.now;

  static const String channelKey = 'android_update_channel';

  static const String lastCheckedKey = 'android_update_last_checked_at';

  static const Duration startupCheckInterval = Duration(days: 1);

  static const MethodChannel _installChannel = MethodChannel(
    'org.spectrum3847.spectrumstrategy/apk_installer',
  );

  final DesktopUpdateService _updateService;
  final http.Client _client;
  final Future<SharedPreferences> Function() _prefsLoader;
  final Future<Directory> Function() _cacheDirLoader;
  final Future<AndroidInstallOutcome> Function(String path) _installer;
  final bool Function() _isAndroid;
  final DateTime Function() _now;

  String? _pendingUrl;
  String? _pendingPath;

  Future<DesktopUpdateChannel> currentChannel() async {
    final prefs = await _prefsLoader();
    return DesktopUpdateChannel.fromName(prefs.getString(channelKey));
  }

  Future<void> setChannel(DesktopUpdateChannel channel) async {
    final prefs = await _prefsLoader();
    await prefs.setString(channelKey, channel.name);
  }

  Future<bool> dueForStartupCheck() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(lastCheckedKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    if (last == null) return true;
    return _now().toUtc().difference(last.toUtc()) >= startupCheckInterval;
  }

  Future<void> _markCheckedNow() async {
    final prefs = await _prefsLoader();
    await prefs.setString(lastCheckedKey, _now().toUtc().toIso8601String());
  }

  Future<AndroidUpdateCheck> checkForUpdate({
    DesktopUpdateChannel? channel,
    bool ignoreVersionGate = false,
    bool recordCheck = true,
  }) async {
    if (!_isAndroid()) return const AndroidUpdateCheck.notSupported();
    final effectiveChannel = channel ?? await currentChannel();
    final result = await _updateService.checkForUpdate(
      channel: effectiveChannel,
      ignoreVersionGate: ignoreVersionGate,
    );
    if (recordCheck) await _markCheckedNow();
    final update = result.update;
    if (update == null) {
      return result.hasRelease
          ? const AndroidUpdateCheck.upToDate()
          : const AndroidUpdateCheck.noRelease();
    }
    return AndroidUpdateCheck(
      hasRelease: true,
      update: AndroidUpdateInfo(
        currentVersion: update.currentVersion,
        latestVersion: update.latestVersion,
        releaseUrl: update.releaseUrl,
        apkUrl: update.assetUrl,
        expectedSha256: update.expectedSha256,
      ),
    );
  }

  Future<AndroidInstallOutcome> downloadAndInstall(
    AndroidUpdateInfo update,
  ) async {
    final url = update.apkUrl;
    final digest = update.expectedSha256;
    if (url == null || digest == null || digest.isEmpty) {
      throw StateError('This release has no verifiable APK to install');
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme != 'https') {
      throw StateError('Refusing a non-https download URL');
    }

    String path;
    if (_pendingUrl == url &&
        _pendingPath != null &&
        await File(_pendingPath!).exists()) {
      path = _pendingPath!;
    } else {
      final response = await _downloadVerified(parsed, digest);
      final cacheDir = await _cacheDirLoader();
      final updateDir = Directory('${cacheDir.path}/update');
      if (await updateDir.exists()) {
        await updateDir.delete(recursive: true);
      }
      await updateDir.create(recursive: true);
      final safeVersion = update.latestVersion.replaceAll(
        RegExp(r'[^A-Za-z0-9_.-]'),
        '_',
      );
      final file = File(
        '${updateDir.path}/spectrum-strategy-$safeVersion-'
        '${_now().millisecondsSinceEpoch}.apk',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      path = file.path;
    }

    final outcome = await _installer(path);
    if (outcome == AndroidInstallOutcome.permissionRequired) {
      _pendingUrl = url;
      _pendingPath = path;
    } else {
      _pendingUrl = null;
      _pendingPath = null;
    }
    return outcome;
  }

  Future<http.Response> _downloadVerified(
    Uri url,
    String expectedSha256,
  ) async {
    var target = url;
    http.Response? response;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('GET', target)..followRedirects = false;
      final streamed = await _client.send(request);
      final hopResponse = await http.Response.fromStream(streamed);
      if (!_isRedirect(hopResponse.statusCode)) {
        response = hopResponse;
        break;
      }
      target = _redirectTarget(target, hopResponse);
    }
    if (response == null) {
      throw StateError('Update download redirected too many times');
    }
    if (response.statusCode != 200 ||
        response.bodyBytes.length < _minApkBytes) {
      throw StateError('Download failed (status ${response.statusCode})');
    }
    final actual = sha256.convert(response.bodyBytes).toString();
    final expected = expectedSha256.trim().toLowerCase();
    if (!_constantTimeHexEquals(actual, expected)) {
      throw StateError('Downloaded update failed its checksum verification');
    }
    return response;
  }

  static const int _maxRedirects = 5;

  static const int _minApkBytes = 100000;

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static Uri _redirectTarget(Uri from, http.Response response) {
    final location = response.headers['location'];
    if (location == null || location.trim().isEmpty) {
      throw StateError('Update download redirected without a location');
    }
    final next = Uri.tryParse(location.trim());
    if (next == null) {
      throw StateError('Update download redirected to an unreadable URL');
    }
    final resolved = from.resolveUri(next);
    if (resolved.scheme != 'https') {
      throw StateError('Refusing to follow a non-https update redirect');
    }
    return resolved;
  }

  static bool _constantTimeHexEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  @visibleForTesting
  static ({String? url, String? digest}) apkAsset(dynamic assets) =>
      _apkAsset(assets);

  static ({String? url, String? digest}) _apkAsset(dynamic assets) {
    if (assets is! List) return (url: null, digest: null);
    Map<String, dynamic>? best;
    var bestCreated = DateTime.fromMillisecondsSinceEpoch(0);
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      final dl = asset['browser_download_url'] as String? ?? '';
      if (!name.endsWith('.apk') || dl.isEmpty) continue;
      final createdRaw = asset['created_at'] as String?;
      final created =
          (createdRaw == null ? null : DateTime.tryParse(createdRaw)) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (best == null || created.isAfter(bestCreated)) {
        best = asset;
        bestCreated = created;
      }
    }
    if (best == null) return (url: null, digest: null);
    final rawDigest = best['digest'] as String?;
    final digest = rawDigest?.replaceFirst(RegExp('^sha256:'), '');
    return (url: best['browser_download_url'] as String?, digest: digest);
  }

  static bool _defaultIsAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<AndroidInstallOutcome> _defaultInstaller(String path) async {
    final result = await _installChannel.invokeMethod<Object?>('install', {
      'path': path,
    });
    return result == 'permission_required'
        ? AndroidInstallOutcome.permissionRequired
        : AndroidInstallOutcome.installed;
  }
}
