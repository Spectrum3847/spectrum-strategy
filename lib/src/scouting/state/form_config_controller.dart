import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/scout_config.dart';
import '../services/firestore_scout_config_service.dart';
import '../services/scout_config_service.dart';

abstract class FormConfigController extends ChangeNotifier {
  FormConfigController({
    required this._service,
    required this._label,
    this._syncService,
  });

  final ScoutConfigService _service;
  final ScoutConfigSyncService? _syncService;

  final String _label;

  ScoutConfig _config = ScoutConfigService.seedConfig;
  Future<void>? _bootstrapFuture;
  StreamSubscription<ScoutConfig?>? _remoteSubscription;

  ScoutConfig get config => _config;

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
    final stored = await _service.loadStored();
    final bundled = await _service.loadDefault();
    if (stored == null) {
      _config = bundled;
    } else if (bundled.revision > stored.revision) {
      _config = bundled;
      unawaited(_service.save(bundled));
      _autoPush(bundled);
    } else {
      _config = stored;
    }
    notifyListeners();

    final sync = _syncService;
    if (sync != null) {
      _remoteSubscription = sync.configStream.listen(_onRemoteConfig);
      try {
        await sync.initialize();
      } catch (_) {}
    }
  }

  void _onRemoteConfig(ScoutConfig? remoteConfig) {
    if (remoteConfig == null) {
      _seedRemoteIfAbsent();
      return;
    }
    if (remoteConfig.revision > _config.revision) {
      final invalid = remoteConfig.validationError;
      if (invalid != null) {
        debugPrint('Ignoring invalid remote $_label config: $invalid');
        return;
      }
      _config = remoteConfig;
      notifyListeners();
      unawaited(_service.save(remoteConfig));
      return;
    }
    if (remoteConfig.revision < _config.revision) {
      _autoPush(_config);
      return;
    }
  }

  bool _seedAttempted = false;

  void _seedRemoteIfAbsent() {
    if (_seedAttempted) return;
    _seedAttempted = true;
    _autoPush(_config);
  }

  Future<void> updateConfig(ScoutConfig config) async {
    final revision = config.revision > _config.revision
        ? config.revision
        : _config.revision;
    final next = config.copyWith(revision: revision + 1);
    _config = next;
    notifyListeners();
    await _service.save(next);
    _autoPush(next);
  }

  Future<void> loadFromJsonString(String jsonString) async {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Config JSON must be an object.');
    }
    final config = ScoutConfig.fromJson(decoded);
    if (config.sections.isEmpty) {
      throw const FormatException('Config has no sections.');
    }

    final invalid = config.validationError;
    if (invalid != null) throw FormatException(invalid);
    await updateConfig(config);
  }

  void _autoPush(ScoutConfig config) {
    final sync = _syncService;
    if (sync == null) return;
    unawaited(() async {
      try {
        await sync.push(config);
      } catch (e) {
        debugPrint('Failed to auto-push $_label config: $e');
      }
    }());
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
