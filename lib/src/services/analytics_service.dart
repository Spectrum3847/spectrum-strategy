import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;

import 'package:flutter/foundation.dart'
    show
        debugPrint,
        defaultTargetPlatform,
        kIsWeb,
        TargetPlatform,
        visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'http_timeout_client.dart';

abstract class AnalyticsService {
  Future<void> start();
  void screen(String name);
  void capture(String event, {Map<String, Object?> properties});
  void identify(String uid);
  void reset();
}

class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> start() async {}

  @override
  void screen(String name) {}

  @override
  void capture(String event, {Map<String, Object?> properties = const {}}) {}

  @override
  void identify(String uid) {}

  @override
  void reset() {}
}

typedef AnalyticsEventSender = Future<void> Function(
  Uri url,
  Map<String, Object?> body,
);

enum _Mode { plugin, http }

class PostHogAnalyticsService implements AnalyticsService {
  PostHogAnalyticsService({
    Posthog? posthog,
    AnalyticsEventSender? sender,
    Future<SharedPreferences> Function()? prefs,

    @visibleForTesting String? debugApiKey,
    @visibleForTesting bool? debugForceHttpFallback,
  }) : _posthog = posthog ?? Posthog(),
       _sender = sender ?? _defaultSender,
       _prefsLoader = prefs ?? SharedPreferences.getInstance,
       _apiKey = debugApiKey ?? _envApiKey,
       _forceHttpFallback = debugForceHttpFallback ?? false;

  static const String _envApiKey = String.fromEnvironment('POSTHOG_API_KEY');
  static const String _host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );
  static const String _distinctIdKey = 'analytics_distinct_id';

  final Posthog _posthog;
  final AnalyticsEventSender _sender;
  final Future<SharedPreferences> Function() _prefsLoader;
  final String _apiKey;
  final bool _forceHttpFallback;

  _Mode? _mode;
  String? _distinctId;

  static bool get _pluginSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get _httpFallbackSupported =>
      _forceHttpFallback ||
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<void> start() async {
    if (_apiKey.isEmpty) return;
    if (!_forceHttpFallback && _pluginSupported) {
      try {
        final config = PostHogConfig(_apiKey)
          ..host = _host
          ..debug = false
          ..sessionReplay = false
          ..personProfiles = PostHogPersonProfiles.identifiedOnly;
        config.sessionReplayConfig.captureNativeScreens = false;

        config.errorTrackingConfig.captureFlutterErrors = true;
        config.errorTrackingConfig.capturePlatformDispatcherErrors = true;
        config.errorTrackingConfig.captureIsolateErrors = true;
        config.errorTrackingConfig.captureNativeExceptions = true;
        await _posthog.setup(config);
        _mode = _Mode.plugin;
      } catch (error) {
        _logFailure('start', error);
      }
      return;
    }
    if (_httpFallbackSupported) {
      try {
        _distinctId = await _loadOrCreateDistinctId();
        _mode = _Mode.http;
      } catch (error) {
        _logFailure('start', error);
      }
    }
  }

  @override
  void screen(String name) {
    switch (_mode) {
      case _Mode.plugin:
        _run('screen', () => _posthog.screen(screenName: name));
      case _Mode.http:
        _post('\$screen', {'\$screen_name': name});
      case null:
        return;
    }
  }

  @override
  void capture(String event, {Map<String, Object?> properties = const {}}) {
    switch (_mode) {
      case _Mode.plugin:
        _run(
          'capture',
          () => _posthog.capture(
            eventName: event,
            properties: properties.isEmpty
                ? null
                : properties.map((k, v) => MapEntry(k, v as Object)),
          ),
        );
      case _Mode.http:
        _post(event, properties);
      case null:
        return;
    }
  }

  @override
  void identify(String uid) {
    if (uid.isEmpty) return;
    switch (_mode) {
      case _Mode.plugin:
        _run('identify', () => _posthog.identify(userId: uid));
      case _Mode.http:
        final previous = _distinctId;
        _distinctId = uid;
        unawaited(_persistDistinctId(uid));
        _post('\$identify', {
          if (previous != null && previous != uid)
            '\$anon_distinct_id': previous,
        });
      case null:
        return;
    }
  }

  @override
  void reset() {
    switch (_mode) {
      case _Mode.plugin:
        _run('reset', () => _posthog.reset());
      case _Mode.http:
        final newId = const Uuid().v4();
        _distinctId = newId;
        unawaited(_persistDistinctId(newId));
      case null:
        return;
    }
  }

  Future<String> _loadOrCreateDistinctId() async {
    final prefs = await _prefsLoader();
    final existing = prefs.getString(_distinctIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_distinctIdKey, id);
    return id;
  }

  Future<void> _persistDistinctId(String id) async {
    final prefs = await _prefsLoader();
    await prefs.setString(_distinctIdKey, id);
  }

  void _post(String event, Map<String, Object?> properties) {
    final body = <String, Object?>{
      'api_key': _apiKey,
      'event': event,
      'distinct_id': _distinctId ?? 'anonymous',
      'properties': {...properties, '\$lib': 'spectrum-strategy-dart'},
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    unawaited(
      _sender(
        Uri.parse('$_host/i/v0/e/'),
        body,
      ).catchError((Object error) => _logFailure('http capture', error)),
    );
  }

  static Future<void> _defaultSender(Uri url, Map<String, Object?> body) async {
    final client = TimeoutHttpClient(timeout: const Duration(seconds: 10));
    try {
      await client.post(
        url,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } finally {
      client.close();
    }
  }

  void _run(String what, Future<void> Function() call) {
    call().catchError((Object error) => _logFailure(what, error));
  }

  void _logFailure(String what, Object error) {
    if (error is MissingPluginException) return;
    debugPrint('PostHog $what failed: $error');
  }
}
