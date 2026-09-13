import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tba_client/tba_client.dart';
import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/services/team_avatar_service.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/widgets/strategy_field_canvas.dart';

import 'support/fake_match_directory.dart';

const String _sampleAvatarBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

TeamAvatarService _avatarService() {
  final mock = MockClient((_) async {
    return http.Response(
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'avatar',
          'details': <String, dynamic>{'base64Image': _sampleAvatarBase64},
        },
      ]),
      200,
    );
  });
  return TeamAvatarService(
    client: TbaClient(config: InMemoryTbaConfig('k'), httpClient: mock),
    year: 2026,
    prefsLoader: SharedPreferences.getInstance,
  );
}

Future<StrategyController> _controllerWithPlacedRobot() async {
  final controller = StrategyController(directory: FakeMatchDirectory());
  await controller.bootstrap();
  controller.loadTeamsFromText('3847');
  controller.selectPhase(StrategyPhase.auton);
  controller.setSelectedRobotTeam(3847);
  controller.selectTool(StrategyTool.robot);
  controller.placeRobot(const StrategyPoint(0.5, 0.5));
  return controller;
}

Widget _harness(StrategyController controller, TeamAvatarService? service) {
  return MaterialApp(
    home: SizedBox(
      width: 800,
      height: 400,
      child: StrategyFieldCanvas(
        controller: controller,
        repaintKey: GlobalKey(),
        fieldAspectRatio: 2.0,
        teamAvatarService: service,
      ),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('team number badge stays visible once an avatar has loaded', (
    tester,
  ) async {
    final controller = await _controllerWithPlacedRobot();
    await tester.pumpWidget(_harness(controller, _avatarService()));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('3847'), findsOneWidget);

    controller.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'team number badge and fallback both show when there is no avatar',
    (tester) async {
      final controller = await _controllerWithPlacedRobot();
      await tester.pumpWidget(_harness(controller, null));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNothing);
      expect(find.text('3847'), findsNWidgets(2));

      controller.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the board announces what is drawn on it', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await _controllerWithPlacedRobot();
    await tester.pumpWidget(_harness(controller, null));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp(r'^Strategy board, Auton phase, 1 robot$', multiLine: true),
      ),
      findsOneWidget,
    );

    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.1, 0.1));
    controller.extendStroke(const StrategyPoint(0.2, 0.2));
    controller.finishStroke();
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Strategy board, Auton phase, 1 drawing, 1 robot$',
          multiLine: true,
        ),
      ),
      findsOneWidget,
    );

    controller.dispose();
    await tester.pumpAndSettle();
    handle.dispose();
  });
}
