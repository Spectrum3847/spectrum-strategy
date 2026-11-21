import 'dart:async';

import 'package:spectrumstrategy/src/services/firestore_active_event_service.dart';

class FakeActiveEventSyncService implements ActiveEventSyncService {
  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();

  final List<String> pushedKeys = <String>[];

  @override
  Stream<String?> get eventKeyStream => _controller.stream;

  @override
  Future<void> initialize() async {}

  void emit(String? eventKey) {
    _controller.add(eventKey);
  }

  @override
  Future<void> push(String eventKey) async {
    pushedKeys.add(eventKey);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
