import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart';

import '../../services/desktop_poll_backoff.dart';
import '../../services/pending_push_queue.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/scout_config.dart';
import 'firestore_scout_config_service.dart';

class DesktopScoutConfigSyncService implements ScoutConfigSyncService {
  DesktopScoutConfigSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue(),
       _docId = 'scoutConfig';

  DesktopScoutConfigSyncService.pit({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue(),
       _docId = 'pitScoutConfig';

  DesktopScoutConfigSyncService.prescout({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue(),
       _docId = 'prescoutConfig';

  static const String _collection = 'appConfig';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final PendingPushQueue _queue;
  final String _docId;
  String get _docPath => '$_collection/$_docId';

  final StreamController<ScoutConfig?> _configController =
      StreamController<ScoutConfig?>.broadcast();
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );
  String? _lastConfigJson;

  ScoutConfig? _pendingConfig;

  @override
  Stream<ScoutConfig?> get configStream => _configController.stream;

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    _pollScheduler.cancel();
    if (snapshot.state == SpectrumAuthState.signedIn) {
      unawaited(_tick());
      _pollScheduler.start(_tick);
    }
  }

  Future<void> _writeChain = Future<void>.value();

  Future<void> _tick() {
    final next = _writeChain.then((_) => _flushPending()).then((_) => _fetch());
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    final config = _pendingConfig;
    if (config == null) return;
    try {
      await _writeConfig(config);
      await _queue.clear(_collection, _docId);
      _pendingConfig = null;
    } catch (_) {}
  }

  Future<void> _fetch() async {
    try {
      final doc = await _firestore.getDocument(_docPath);
      final raw = doc?.fields['configJson'];
      _pollScheduler.onSuccess();
      if (raw is! String) {
        if (_lastConfigJson != null || doc == null) {
          _lastConfigJson = null;
          _emit(null);
        }
        return;
      }
      if (raw == _lastConfigJson) {
        return;
      }
      final config = ScoutConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _lastConfigJson = raw;
      _emit(config);
    } catch (error) {
      debugPrint('Desktop scout config sync error: $error');
      _pollScheduler.onFailure();
    }
  }

  @override
  Future<void> push(ScoutConfig config) {
    final next = _writeChain.then((_) async {
      try {
        await _writeConfig(config);
        await _queue.clear(_collection, _docId);
        _pendingConfig = null;
      } catch (error) {
        _pendingConfig = config;
        await _queue.mark(_collection, _docId);
        rethrow;
      }
    });
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _writeConfig(ScoutConfig config) {
    return _firestore.setDocument(_docPath, <String, dynamic>{
      'configJson': jsonEncode(config.toJson()),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _configController.close();
  }

  void _emit(ScoutConfig? config) {
    if (!_configController.isClosed) {
      _configController.add(config);
    }
  }
}
