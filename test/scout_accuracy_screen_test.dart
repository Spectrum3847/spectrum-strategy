import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/ui/scout_accuracy_screen.dart';
import 'package:tba_client/tba_client.dart';

import 'support/fake_scouting_storage.dart';
import 'support/scouter_opr_fixtures.dart';

const _rotation = <List<String>>[
  ['Alice', 'Bob', 'Cara', 'Dev', 'Eli', 'Zed'],
  ['Alice', 'Cara', 'Dev', 'Bob', 'Eli', 'Dev'],
  ['Bob', 'Dev', 'Eli', 'Alice', 'Cara', 'Eli'],
  ['Cara', 'Eli', 'Alice', 'Bob', 'Dev', 'Cara'],
  ['Dev', 'Alice', 'Bob', 'Cara', 'Eli', 'Alice'],
  ['Eli', 'Bob', 'Cara', 'Alice', 'Dev', 'Bob'],
  ['Alice', 'Dev', 'Eli', 'Cara', 'Bob', 'Eli'],
  ['Bob', 'Cara', 'Alice', 'Eli', 'Dev', 'Cara'],
];
const _miss = <String, int>{'Alice': -20, 'Bob': 15};

({List<TbaScheduleMatch> matches, List<ScoutEntry> entries}) _event() {
  final matches = <TbaScheduleMatch>[];
  final entries = <ScoutEntry>[];
  for (var m = 0; m < _rotation.length; m++) {
    final number = m + 1;
    final teams = <int>[for (var i = 0; i < 6; i++) 100 * number + i];
    var red = 0;
    var blue = 0;
    for (var i = 0; i < 6; i++) {
      final scout = _rotation[m][i];
      const truth = 40;
      if (i < 3) {
        red += truth;
      } else {
        blue += truth;
      }
      entries.add(
        fuelEntry(number, teams[i], scout, truth - (_miss[scout] ?? 0)),
      );
    }
    matches.add(
      tbaMatch(
        number,
        red: teams.sublist(0, 3),
        blue: teams.sublist(3),
        redFuel: red,
        blueFuel: blue,
      ),
    );
  }
  return (matches: matches, entries: entries);
}

void main() {
  Future<ScoutingController> controllerWith(List<ScoutEntry> entries) async {
    final controller = ScoutingController(storage: FakeScoutingStorage());
    await controller.bootstrap();
    for (final entry in entries) {
      await controller.saveEntry(entry);
    }
    return controller;
  }

  Future<void> pump(
    WidgetTester tester, {
    required ScoutingController controller,
    required FetchOfficialMatches fetch,
    String eventKey = '2026test',
    Size size = const Size(800, 1200),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ScoutAccuracyScreen(
          scoutingController: controller,
          eventKey: eventKey,
          fetchMatches: fetch,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists scouts by distance from zero, thin data last', (
    tester,
  ) async {
    final event = _event();
    await pump(
      tester,
      controller: await controllerWith(event.entries),
      fetch: (_) async => event.matches,
    );

    expect(find.text('Scout accuracy'), findsOneWidget);
    expect(find.textContaining('For coaching, not blame'), findsOneWidget);
    expect(find.textContaining('16 alliances used'), findsOneWidget);
    expect(find.text('Not enough data yet'), findsOneWidget);

    final names = <String>['Alice', 'Bob', 'Cara', 'Dev', 'Eli', 'Zed'];
    final dy = <String, double>{
      for (final name in names) name: tester.getTopLeft(find.text(name)).dy,
    };
    expect(dy['Alice']!, lessThan(dy['Bob']!));
    expect(dy['Bob']!, lessThan(dy['Cara']!));
    expect(dy['Zed']!, greaterThan(dy['Eli']!));
    expect(find.text('Coach'), findsWidgets);
  });

  testWidgets('shows the signed miss with one decimal', (tester) async {
    final event = _event();
    await pump(
      tester,
      controller: await controllerWith(event.entries),
      fetch: (_) async => event.matches,
    );

    expect(find.textContaining(RegExp(r'^\+\d+\.\d$')), findsWidgets);
    expect(find.textContaining(RegExp(r'^-\d+\.\d$')), findsWidgets);
  });

  test('formatScoutMiss signs and rounds', () {
    expect(formatScoutMiss(3.24), '+3.2');
    expect(formatScoutMiss(-3.26), '-3.3');
    expect(formatScoutMiss(0.04), '0.0');
    expect(formatScoutMiss(-0.04), '0.0');
  });

  testWidgets('refresh fetches the official counts again', (tester) async {
    final event = _event();
    var calls = 0;
    await pump(
      tester,
      controller: await controllerWith(event.entries),
      fetch: (_) async {
        calls++;
        return event.matches;
      },
    );
    expect(calls, 1);

    await tester.tap(find.byTooltip('Refresh official counts'));
    await tester.pumpAndSettle();

    expect(calls, 2);
  });

  testWidgets('a refresh shows the newly posted matches', (tester) async {
    final event = _event();
    var posted = 0;
    await pump(
      tester,
      controller: await controllerWith(event.entries),
      fetch: (_) async => event.matches.take(posted).toList(),
    );
    expect(find.textContaining('No played matches with fuel'), findsOneWidget);

    posted = event.matches.length;
    await tester.tap(find.byTooltip('Refresh official counts'));
    await tester.pumpAndSettle();

    expect(find.textContaining('16 alliances used'), findsOneWidget);
  });

  testWidgets('a failed refresh after an empty load says it failed', (
    tester,
  ) async {
    var fail = false;
    await pump(
      tester,
      controller: await controllerWith(const <ScoutEntry>[]),
      fetch: (_) async {
        if (fail) throw TbaApiException(503, 'down');
        return const <TbaScheduleMatch>[];
      },
    );

    fail = true;
    await tester.tap(find.byTooltip('Refresh official counts'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be reached'), findsOneWidget);
  });

  testWidgets('a rejected TBA key says to replace it', (tester) async {
    await pump(
      tester,
      controller: await controllerWith(const <ScoutEntry>[]),
      fetch: (_) async => throw TbaApiException(401, 'bad key'),
    );

    expect(find.textContaining('rejected the team TBA key'), findsOneWidget);
  });

  testWidgets('a scout row reads as one label', (tester) async {
    final event = _event();
    await pump(
      tester,
      controller: await controllerWith(event.entries),
      fetch: (_) async => event.matches,
    );

    expect(
      find.bySemanticsLabel(
        RegExp(r'^Alice, -[0-9.]+ fuel per robot per match, '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no event says to load one and fetches nothing', (tester) async {
    var calls = 0;
    await pump(
      tester,
      controller: await controllerWith(const <ScoutEntry>[]),
      eventKey: '',
      fetch: (_) async {
        calls++;
        return const <TbaScheduleMatch>[];
      },
    );

    expect(find.textContaining('Load an event'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('an unreachable TBA says so', (tester) async {
    await pump(
      tester,
      controller: await controllerWith(const <ScoutEntry>[]),
      fetch: (_) async => throw TbaApiException(503, 'down'),
    );

    expect(find.textContaining('could not be reached'), findsOneWidget);
  });

  testWidgets('a missing TBA key says how to fix it', (tester) async {
    await pump(
      tester,
      controller: await controllerWith(const <ScoutEntry>[]),
      fetch: (_) async => throw const TbaApiKeyMissingException(),
    );

    expect(find.textContaining('API key is not configured'), findsOneWidget);
  });

  testWidgets('no played matches with fuel counts', (tester) async {
    await pump(
      tester,
      controller: await controllerWith(const <ScoutEntry>[]),
      fetch: (_) async => <TbaScheduleMatch>[
        tbaMatch(1, red: [1, 2, 3], blue: [4, 5, 6]),
      ],
    );

    expect(find.textContaining('No played matches with fuel'), findsOneWidget);
  });

  testWidgets('official counts but no complete alliance yet', (tester) async {
    final event = _event();
    await pump(
      tester,
      controller: await controllerWith(event.entries.take(2).toList()),
      fetch: (_) async => event.matches,
    );

    expect(find.textContaining('No complete alliances yet'), findsOneWidget);
    expect(find.textContaining('0 alliances used'), findsOneWidget);
  });

  testWidgets('holds up at 200% text on a small phone', (tester) async {
    final event = _event();
    await pump(
      tester,
      controller: await controllerWith(event.entries),
      fetch: (_) async => event.matches,
      size: const Size(360, 760),
      textScale: 2,
    );

    await tester.scrollUntilVisible(find.text('Alice'), 200);
    await tester.scrollUntilVisible(find.text('Not enough data yet'), 200);
    expect(tester.takeException(), isNull);
  });
}
