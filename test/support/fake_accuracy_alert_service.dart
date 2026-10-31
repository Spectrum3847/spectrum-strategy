import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/accuracy_alert.dart';
import 'package:spectrumstrategy/src/scouting/services/accuracy_alert_service.dart';

class FakeAccuracyAlertService implements AccuracyAlertService {
  final StreamController<List<AccuracyAlert>> _controller =
      StreamController<List<AccuracyAlert>>.broadcast();

  List<AccuracyAlert> _alerts = const <AccuracyAlert>[];
  final List<String> acknowledged = <String>[];
  int initializeCalls = 0;

  @override
  Stream<List<AccuracyAlert>> get alertsStream => _controller.stream;

  @override
  List<AccuracyAlert> get pendingAlerts =>
      List<AccuracyAlert>.unmodifiable(_alerts);

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> acknowledge(String entryId) async {
    acknowledged.add(entryId);
    _alerts = _alerts
        .where((a) => a.entryId != entryId)
        .toList(growable: false);
    _emit(_alerts);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emitAlerts(List<AccuracyAlert> alerts) {
    _alerts = alerts;
    _emit(_alerts);
  }

  void _emit(List<AccuracyAlert> alerts) {
    if (!_controller.isClosed) {
      _controller.add(alerts);
    }
  }
}
