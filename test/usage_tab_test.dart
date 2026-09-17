import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/usage_rollup.dart';
import 'package:spectrumstrategy/src/services/usage_rollup_service.dart';
import 'package:spectrumstrategy/src/ui/usage_tab.dart';

class _FakeService implements UsageRollupService {
  _FakeService(this._result);

  final Object _result;
  int calls = 0;

  @override
  Future<UsageRollup> fetch() async {
    calls++;
    if (_result is UsageRollup) return _result;
    throw _result;
  }
}

UsageRollup _rollup({
  int events = 12,
  List<UsageCount> tabs = const [
    UsageCount('Scout', 7),
    UsageCount('Strategy', 5),
  ],
}) => UsageRollup(
  updatedAt: DateTime.utc(2026, 8, 16, 6, 25),
  windowDays: 30,
  eventsCounted: events,
  deviceCount: 3,
  tabs: tabs,
  platforms: const [UsageCount('android', 12)],
  appVersions: const [UsageCount('1.0.0', 12)],
  daily: const [UsageDay('2026-08-15', 4), UsageDay('2026-08-16', 8)],
);

Future<void> _pump(WidgetTester tester, UsageRollupService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: UsageTab(service: service)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ranks tabs with their counts next to them', (tester) async {
    await _pump(tester, _FakeService(_rollup()));

    expect(find.text('Scout'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Strategy'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('every bar carries its value, so colour is never the only cue', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeService(
        _rollup(
          tabs: const [
            UsageCount('Scout', 7),
            UsageCount('Strategy', 5),
            UsageCount('Docs', 1),
          ],
        ),
      ),
    );

    for (final value in ['7', '5', '1']) {
      expect(find.text(value), findsWidgets, reason: 'missing label $value');
    }
  });

  testWidgets('shows how old the numbers are', (tester) async {
    await _pump(tester, _FakeService(_rollup()));

    expect(find.textContaining('2026-08-16'), findsWidgets);
    expect(find.textContaining('once a day'), findsOneWidget);
  });

  testWidgets('a rollup that counted nothing says so, and draws no charts', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeService(
        UsageRollup.fromJson(const {'windowDays': 30, 'eventsCounted': 0}),
      ),
    );

    expect(find.text('Nothing recorded yet'), findsOneWidget);
    expect(find.text('Tabs opened'), findsNothing);
  });

  testWidgets('a denied read explains the role rather than failing blank', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeService(
        const UsageRollupUnavailable(
          'Usage data is limited to the developer role.',
        ),
      ),
    );

    expect(find.text('No usage data'), findsOneWidget);
    expect(find.textContaining('developer role'), findsOneWidget);
  });

  testWidgets('a failed read can be retried', (tester) async {
    final service = _FakeService(
      const UsageRollupUnavailable('Could not read usage data.'),
    );
    await _pump(tester, service);
    expect(service.calls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(service.calls, 2);
  });

  testWidgets('a single day of data does not divide by zero', (tester) async {
    await _pump(
      tester,
      _FakeService(
        UsageRollup.fromJson(const {
          'windowDays': 30,
          'eventsCounted': 1,
          'deviceCount': 1,
          'tabs': [
            {'name': 'Scout', 'count': 1},
          ],
          'daily': [
            {'date': '2026-08-16', 'count': 1},
          ],
        }),
      ),
    );

    expect(find.text('Tabs opened'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero-count row still renders rather than vanishing', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeService(
        _rollup(tabs: const [UsageCount('Scout', 7), UsageCount('Docs', 0)]),
      ),
    );

    expect(find.text('Docs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
