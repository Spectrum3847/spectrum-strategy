import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/state/event_sections_controller.dart';
import 'package:spectrumstrategy/src/widgets/event_sections_view.dart';

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient() : super(config: InMemoryTbaConfig('test-key'));

  @override
  Future<TbaEventRankings?> getEventRankings(String eventKey) async =>
      TbaEventRankings.fromJson(eventKey, <String, dynamic>{
        'rankings': <dynamic>[
          <String, dynamic>{
            'rank': 1,
            'team_key': 'frc254',
            'record': <String, dynamic>{'wins': 8, 'losses': 1, 'ties': 0},
            'matches_played': 9,
            'dq': 0,
            'qual_average': null,
            'sort_orders': <dynamic>[3.11],
          },
        ],
        'sort_order_info': <dynamic>[
          <String, dynamic>{'name': 'Ranking Score'},
        ],
      });

  @override
  Future<TbaEventAlliances?> getEventAlliances(String eventKey) async =>
      TbaEventAlliances.fromJson(eventKey, <dynamic>[
        <String, dynamic>{
          'name': 'Alliance 1',
          'picks': <dynamic>['frc254', 'frc118', 'frc2056'],
          'status': <String, dynamic>{'status': 'won'},
        },
      ]);

  @override
  Future<TbaEventAwards?> getEventAwards(String eventKey) async =>
      TbaEventAwards.fromJson(eventKey, <dynamic>[]);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<EventSectionsController> pump(WidgetTester tester) async {
    final controller = EventSectionsController(tbaClient: _FakeTbaClient());
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventSectionsView(
            controller: controller,
            onSelectionChanged: () => controller.load('2026txhou'),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('it opens on the picker, not on a wall of tables', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Sections'), findsOneWidget);
    expect(find.text('Rankings'), findsNothing);
    expect(find.textContaining('always shown'), findsOneWidget);
  });

  testWidgets('the picker can turn everything on', (tester) async {
    final controller = await pump(tester);

    await tester.tap(find.text('Sections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(controller.visible, EventSection.values.toSet());
  });

  testWidgets('an enabled section renders its data', (tester) async {
    final controller = await pump(tester);

    await controller.toggle(EventSection.rankings);
    await controller.load('2026txhou');
    await tester.pumpAndSettle();

    expect(find.text('Rankings'), findsOneWidget);
    expect(find.text('Ranking Score'), findsOneWidget);

    expect(find.text('254'), findsOneWidget);
    expect(find.text('8-1-0'), findsOneWidget);
  });

  testWidgets('a section with no data yet says so instead of looking broken', (
    tester,
  ) async {
    final controller = await pump(tester);

    await controller.toggle(EventSection.awards);
    await controller.load('2026txhou');
    await tester.pumpAndSettle();

    expect(find.textContaining('after the awards ceremony'), findsOneWidget);
  });

  testWidgets('alliances read in pick order', (tester) async {
    final controller = await pump(tester);

    await controller.toggle(EventSection.alliances);
    await controller.load('2026txhou');
    await tester.pumpAndSettle();

    expect(find.text('Alliance 1'), findsOneWidget);
    expect(find.text('254, 118, 2056'), findsOneWidget);
  });
}
