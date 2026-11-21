import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart';

import '../../services/desktop_poll_backoff.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/accuracy_alert.dart';
import 'accuracy_alert_service.dart';

class DesktopAccuracyAlertService implements AccuracyAlertService {
  DesktopAccuracyAlertService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 60),
  });

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;

  final StreamController<List<AccuracyAlert>> _controller =
      StreamController<List<AccuracyAlert>>.broadcast();

  List<AccuracyAlert> _alerts = const <AccuracyAlert>[];
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<List<AccuracyAlert>> get alertsStream => _controller.stream;

  @override
  List<AccuracyAlert> get pendingAlerts =>
      List<AccuracyAlert>.unmodifiable(_alerts);

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    _pollScheduler.cancel();

    _alerts = const <AccuracyAlert>[];
    _emit(_alerts);
    if (snapshot.state == SpectrumAuthState.signedIn && snapshot.user != null) {
      final uid = snapshot.user!.uid;
      unawaited(_poll(uid));
      _pollScheduler.start(() => _poll(uid));
    }
  }

  Future<void> _poll(String uid) async {
    try {
      final docs = await _firestore.runQuery(
        'accuracyAlerts',
        filters: [
          fc.FieldFilter('authorUid', 'EQUAL', uid),
          fc.FieldFilter('acknowledged', 'EQUAL', false),
        ],
        limit: 20,
      );
      _alerts = docs
          .map((doc) {
            try {
              return AccuracyAlert.fromJson(doc.fields);
            } catch (_) {
              return null;
            }
          })
          .whereType<AccuracyAlert>()
          .toList(growable: false);
      _emit(_alerts);
      _pollScheduler.onSuccess();
    } catch (error) {
      debugPrint('DesktopAccuracyAlertService poll error: $error');
      _pollScheduler.onFailure();
    }
  }

  @override
  Future<void> acknowledge(String entryId) async {
    try {
      await _firestore.setDocument(
        'accuracyAlerts/$entryId',
        <String, dynamic>{'acknowledged': true},
        updateMask: const ['acknowledged'],
      );
    } on fc.FirestoreApiException catch (e) {
      if (e.isNotFound || e.statusCode == 403) {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _controller.close();
  }

  void _emit(List<AccuracyAlert> alerts) {
    if (!_controller.isClosed) {
      _controller.add(alerts);
    }
  }
}
