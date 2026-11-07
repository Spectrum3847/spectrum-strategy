import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/services/scout_qr_codec.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_qr_scan_screen.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

const _eventKey = '2026test';

void _useDesktopScanner() {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'scanning a QRScout payload with no loaded schedule still imports, '
    'carrying the typed match number with no tbaMatchKey',
    (tester) async {
      _useDesktopScanner();
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final scouting = ScoutingController(storage: FakeScoutingStorage());
      final config = ScoutConfigController(service: FakeScoutConfigService());
      final event = EventController(client: _NoMatchesClient());
      await Future.wait(<Future<void>>[
        scouting.bootstrap(),
        config.bootstrap(),
        event.setEventKey(_eventKey),
      ]);

      final payload = ScoutQrCodec.encodeQrScout(<String, dynamic>{
        'matchNumber': '12',
        'robot': 'R1',
        'pTnumber': 3847,
      }, config.config);

      await tester.pumpWidget(
        MaterialApp(
          home: ScoutQrScanScreen(
            controller: scouting,
            config: config.config,
            eventController: event,
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.widget<TextField>(find.byType(TextField)).onSubmitted!(payload);
      await tester.pumpAndSettle();

      expect(scouting.entries, hasLength(1));
      expect(scouting.entries.single.tbaMatchKey, isNull);

      expect(scouting.entries.single.fieldValues['matchNumber'], 12);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'scanning a QRScout payload resolves tbaMatchKey from the loaded schedule',
    (tester) async {
      _useDesktopScanner();
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final scouting = ScoutingController(storage: FakeScoutingStorage());
      final config = ScoutConfigController(service: FakeScoutConfigService());
      final event = EventController(client: _OneMatchClient());
      await Future.wait(<Future<void>>[
        scouting.bootstrap(),
        config.bootstrap(),
        event.setEventKey(_eventKey),
      ]);

      final payload = ScoutQrCodec.encodeQrScout(<String, dynamic>{
        'matchNumber': '12',
        'robot': 'R1',
        'pTnumber': 3847,
      }, config.config);

      await tester.pumpWidget(
        MaterialApp(
          home: ScoutQrScanScreen(
            controller: scouting,
            config: config.config,
            eventController: event,
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.widget<TextField>(find.byType(TextField)).onSubmitted!(payload);
      await tester.pumpAndSettle();

      expect(scouting.entries, hasLength(1));
      expect(scouting.entries.single.tbaMatchKey, '${_eventKey}_qm12');
      debugDefaultTargetPlatformOverride = null;
    },
  );

  group('on a platform with a camera', () {
    void Function(BarcodeCapture)? onDetect;
    var cameraShown = false;

    Widget camera(BuildContext context, void Function(BarcodeCapture) cb) {
      onDetect = cb;
      cameraShown = true;
      return const SizedBox.expand();
    }

    BarcodeCapture seen(String raw) =>
        BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: raw)]);

    Future<
      ({
        ScoutingController scouting,
        ScoutConfigController config,
        List<int> popped,
      })
    >
    open(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      onDetect = null;
      cameraShown = false;
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      final config = ScoutConfigController(service: FakeScoutConfigService());
      final event = EventController(client: _NoMatchesClient());
      await Future.wait(<Future<void>>[
        scouting.bootstrap(),
        config.bootstrap(),
        event.setEventKey(_eventKey),
      ]);
      final popped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final count = await Navigator.of(context).push<int>(
                  MaterialPageRoute<int>(
                    builder: (_) => ScoutQrScanScreen(
                      controller: scouting,
                      config: config.config,
                      eventController: event,
                      cameraBuilder: camera,
                    ),
                  ),
                );
                if (count != null) popped.add(count);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (scouting: scouting, config: config, popped: popped);
    }

    String payload(ScoutConfigController config, int team) =>
        ScoutQrCodec.encodeQrScout(<String, dynamic>{
          'matchNumber': '12',
          'robot': 'R1',
          'pTnumber': team,
        }, config.config);

    testWidgets('shows the wedge field and tally next to the camera, and a '
        'typed payload imports', (tester) async {
      final s = await open(tester);

      expect(cameraShown, isTrue);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('Imported 0'), findsOneWidget);

      tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
        payload(s.config, 3847),
      );
      await tester.pumpAndSettle();

      expect(s.scouting.entries, hasLength(1));
      expect(find.text('Imported: Team 3847'), findsOneWidget);
      expect(find.textContaining('Imported 1'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('keeps scanning after an import and ignores a code still in '
        'view', (tester) async {
      final s = await open(tester);

      onDetect!(seen(payload(s.config, 3847)));
      await tester.pumpAndSettle();
      onDetect!(seen(payload(s.config, 3847)));
      onDetect!(seen(payload(s.config, 2714)));
      await tester.pumpAndSettle();

      expect(s.scouting.entries.map((e) => e.teamNumber), [3847, 2714]);
      expect(find.textContaining('Imported 2, 0 duplicates'), findsOneWidget);
      expect(find.byType(ScoutQrScanScreen), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('counts an unreadable code as an error and Done reports the '
        'import count', (tester) async {
      final s = await open(tester);

      onDetect!(seen(payload(s.config, 3847)));
      onDetect!(seen('not a scout code'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 error'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(ScoutQrScanScreen), findsNothing);
      expect(s.popped, [1]);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

class _NoMatchesClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return const <StatboticsMatch>[];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}

class _OneMatchClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return <StatboticsMatch>[
      StatboticsMatch(
        key: '${eventKey}_qm12',
        event: eventKey,
        matchNumber: 12,
        compLevel: 'qm',
        redTeams: const <int>[3847, 2714, 245],
        blueTeams: const <int>[33, 67, 111],
      ),
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}
