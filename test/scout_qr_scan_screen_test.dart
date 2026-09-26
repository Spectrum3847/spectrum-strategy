import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
