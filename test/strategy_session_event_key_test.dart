import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';

import 'support/fake_match_directory.dart';

void main() {
  test('a fresh session has no event key', () {
    expect(StrategySession.create().eventKey, isEmpty);
  });

  test('the key round-trips through JSON', () {
    final session = StrategySession.create(eventKey: '2026txdri1');
    final again = StrategySession.fromJson(session.toJson());

    expect(again.eventKey, '2026txdri1');
  });

  test('an empty key is left out of the payload entirely', () {
    expect(StrategySession.create().toJson().containsKey('eventKey'), isFalse);
  });

  test('a stored board from before this field still loads', () {
    final legacy = StrategySession.create().toJson()..remove('eventKey');

    expect(StrategySession.fromJson(legacy).eventKey, isEmpty);
  });

  test('a wrong-typed key falls back to empty rather than throwing', () {
    final json = StrategySession.create().toJson();
    json['eventKey'] = 42;

    expect(StrategySession.fromJson(json).eventKey, isEmpty);
  });

  test('the match summary carries the key', () {
    final summary = MatchSummary.fromSession(
      StrategySession.create(eventKey: '2026txdri1'),
    );

    expect(summary.eventKey, '2026txdri1');
  });

  test('createMatch records the key, and setEventKey updates it', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    await controller.createMatch(
      eventName: 'Test Event',
      eventKey: '2026txdri1',
    );
    expect(controller.session.eventKey, '2026txdri1');

    controller.setEventKey('2026txcmp');
    expect(controller.session.eventKey, '2026txcmp');

    await controller.saveNow();

    final summaries = await controller.listMatches();
    expect(
      summaries.any((MatchSummary s) => s.eventKey == '2026txcmp'),
      isTrue,
      reason: 'the key has to reach storage, not just memory',
    );
  });
}
