import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/event_stat_table.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/widgets/event_stat_table_view.dart';

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient({this.oprs, this.coprs})
    : super(config: InMemoryTbaConfig('test-key'));

  final TbaEventOprs? oprs;
  final TbaEventCoprs? coprs;

  @override
  Future<TbaEventOprs?> getEventOprs(String eventKey) async => oprs;

  @override
  Future<TbaEventCoprs?> getEventCoprs(String eventKey) async => coprs;
}

TbaEventOprs _oprs() => TbaEventOprs.fromJson('2026txhou', <String, dynamic>{
  'oprs': <String, dynamic>{'frc254': 60.0, 'frc118': 40.0},
  'dprs': <String, dynamic>{'frc254': -5.0, 'frc118': -3.0},
  'ccwms': <String, dynamic>{'frc254': 65.0, 'frc118': 43.0},
});

TbaEventCoprs _coprs() => TbaEventCoprs.fromJson('2026txhou', <String, dynamic>{
  'foulPoints': <String, dynamic>{'frc254': 3.1, 'frc118': 2.0},
  'teleopCoralCount': <String, dynamic>{'frc254': 12.5},
});

Future<EventStatsController> _pump(
  WidgetTester tester, {
  TbaEventOprs? oprs,
  TbaEventCoprs? coprs,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = EventStatsController(
    tbaClient: _FakeTbaClient(oprs: oprs, coprs: coprs),
  );
  await controller.bootstrap();
  await controller.load('2026txhou');

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: EventStatTableView(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('shows only the curated default columns, not every stat', (
    tester,
  ) async {
    await _pump(tester, oprs: _oprs(), coprs: _coprs());

    expect(find.text(oprStatName), findsOneWidget);
    expect(find.text('foulPoints'), findsOneWidget);
    expect(find.text(dprStatName), findsNothing);
    expect(find.text('teleopCoralCount'), findsNothing);
  });

  testWidgets('a stat a team does not report renders blank, not zero', (
    tester,
  ) async {
    final controller = await _pump(tester, oprs: _oprs(), coprs: _coprs());
    await controller.toggleColumn('teleopCoralCount');
    await tester.pumpAndSettle();

    expect(find.text('12.50'), findsOneWidget);
    expect(
      find.text('0.00'),
      findsNothing,
      reason: 'a missing measurement must not be rendered as a measured zero',
    );
  });

  testWidgets('the picker offers what the event reports and toggles persist', (
    tester,
  ) async {
    final controller = await _pump(tester, oprs: _oprs(), coprs: _coprs());

    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();

    expect(find.text('teleopCoralCount'), findsOneWidget);
    expect(find.text(ccwmStatName), findsOneWidget);

    await tester.tap(find.text(ccwmStatName));
    await tester.pumpAndSettle();

    expect(controller.selectedColumns, contains(ccwmStatName));
  });

  testWidgets('no stats yet reads as a notice, not an error', (tester) async {
    await _pump(tester);

    expect(find.textContaining('no stats for this event yet'), findsOneWidget);

    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Columns'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the picker offers the defaults before any stats exist', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(
      find.ancestor(
        of: find.text('Columns'),
        matching: find.byType(OutlinedButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('curated default'), findsOneWidget);
    for (final column in defaultStatColumns) {
      expect(find.text(column), findsOneWidget);
    }
  });

  testWidgets('an emptied column selection explains itself', (tester) async {
    final controller = await _pump(tester, oprs: _oprs(), coprs: _coprs());
    for (final column in defaultStatColumns) {
      await controller.toggleColumn(column);
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('No columns chosen'), findsOneWidget);
  });

  testWidgets('sorting by a column puts the biggest number first', (
    tester,
  ) async {
    await _pump(tester, oprs: _oprs(), coprs: _coprs());

    expect(
      tester.getCenter(find.text('118')).dy,
      lessThan(tester.getCenter(find.text('254')).dy),
    );

    await tester.tap(find.text(oprStatName));
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('254')).dy,
      lessThan(tester.getCenter(find.text('118')).dy),
    );
  });

  testWidgets('unticking the sorted column drops the sort, not the table', (
    tester,
  ) async {
    final controller = await _pump(tester, oprs: _oprs(), coprs: _coprs());

    await tester.tap(find.text(oprStatName));
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('254')).dy,
      lessThan(tester.getCenter(find.text('118')).dy),
    );

    await controller.toggleColumn(oprStatName);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(oprStatName), findsNothing);

    expect(
      tester.getCenter(find.text('118')).dy,
      lessThan(tester.getCenter(find.text('254')).dy),
    );
  });
}
