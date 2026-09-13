import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/ui/strategy_tab.dart';

import 'support/fake_match_directory.dart';

const _eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';

Future<EventController> _eventControllerWith(String matchesJson) async {
  Future<http.Response> handler(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/event/2026txhou')) {
      return http.Response(_eventJson, 200);
    }
    if (path.endsWith('/team_events')) return http.Response('[]', 200);
    if (path.endsWith('/matches')) return http.Response(matchesJson, 200);
    return http.Response('not found', 404);
  }

  final controller = EventController(
    client: StatboticsClient(httpClient: MockClient(handler)),
  );
  await controller.setEventKey('2026txhou');
  return controller;
}

void main() {
  testWidgets('Clear all snackbar hides on its own', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: EventController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Clear all'));
    await tester.tap(find.text('Clear all'));

    await tester.pumpAndSettle();
    expect(find.text('Board cleared'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Board cleared'), findsNothing);
  });

  testWidgets('drops team import and the sidebar, keeps clearing the board', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: EventController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Import'), findsNothing);
    expect(find.text('Teams'), findsNothing);
    expect(find.text('Phase note'), findsNothing);
    expect(find.text('Pick match'), findsNothing);

    expect(find.text('Clear phase'), findsOneWidget);
    expect(find.text('Clear all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board header does not overflow at phone width', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: EventController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a manual removeTeam is not undone by a later controller '
      'update', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const matchesJson =
        '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[111,222,333]},'
        '"blue":{"team_keys":[444,555,666]}}}]';
    final eventController = await _eventControllerWith(matchesJson);
    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: eventController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(strategy.session.teamNumbers, [111, 222, 333, 444, 555, 666]);

    strategy.removeTeam(111);
    expect(strategy.session.teamNumbers, [222, 333, 444, 555, 666]);

    strategy.setEventName('Renamed');
    await tester.pump();
    expect(strategy.session.teamNumbers, [222, 333, 444, 555, 666]);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a playoff match number loads its teams', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const matchesJson =
        '[{"key":"2026txhou_sf1m1","event":"2026txhou","match_number":1,'
        '"comp_level":"sf","alliances":{"red":{"team_keys":[777,888]},'
        '"blue":{"team_keys":[999]}}}]';
    final eventController = await _eventControllerWith(matchesJson);
    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: eventController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(strategy.session.teamNumbers, [777, 888, 999]);
    expect(strategy.session.eventKey, '2026txhou');

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('changing the match replaces an untouched roster, not a manually '
      'edited one', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const matchesJson =
        '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[111,222,333]},'
        '"blue":{"team_keys":[444,555,666]}}},'
        '{"key":"2026txhou_qm2","event":"2026txhou","match_number":2,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[777,888,999]},'
        '"blue":{"team_keys":[100,200,300]}}}]';
    final eventController = await _eventControllerWith(matchesJson);
    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: eventController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(strategy.session.teamNumbers, [111, 222, 333, 444, 555, 666]);

    strategy.setMatchNumber('2');
    await tester.pump();
    expect(strategy.session.teamNumbers, [100, 200, 300, 777, 888, 999]);

    strategy.removeTeam(777);
    expect(strategy.session.teamNumbers, [100, 200, 300, 888, 999]);

    strategy.setMatchNumber('1');
    await tester.pump();
    expect(strategy.session.teamNumbers, [100, 200, 300, 888, 999]);

    await tester.pump(const Duration(seconds: 1));
  });
}
