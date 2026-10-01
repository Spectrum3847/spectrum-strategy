import 'package:spectrumstrategy/src/services/analytics_service.dart';

class FakeAnalyticsService implements AnalyticsService {
  int startCalls = 0;
  final List<String> screens = <String>[];
  final List<String> events = <String>[];
  final List<String> identifiedUids = <String>[];
  int resetCalls = 0;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  void screen(String name) {
    screens.add(name);
  }

  @override
  void capture(String event, {Map<String, Object?> properties = const {}}) {
    events.add(event);
  }

  @override
  void identify(String uid) {
    identifiedUids.add(uid);
  }

  @override
  void reset() {
    resetCalls++;
  }
}
