import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  group('theme-aware palette tokens', () {
    Future<void> pumpDatabaseTab(WidgetTester tester, ThemeData theme) async {
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      final config = ScoutConfigController(service: FakeScoutConfigService());
      await scouting.bootstrap();
      await config.bootstrap();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: DatabaseTab(
              scoutingController: scouting,
              configController: config,
              eventController: EventController(),
              canEditAnyEntry: false,
              canAddManualEntry: false,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Database filter bar renders dark surfaces in dark mode', (
      tester,
    ) async {
      await pumpDatabaseTab(tester, buildDarkAppTheme());
      final materials = tester.widgetList<Material>(find.byType(Material));
      expect(
        materials.any((m) => m.color == StrategyPalette.darkSurface),
        isTrue,
        reason: 'the filter bar should sit on the dark surface tone',
      );
      expect(
        materials.any((m) => m.color == StrategyPalette.surface),
        isFalse,
        reason: 'no light surface tone may leak into the dark theme',
      );
    });

    testWidgets('Database filter bar renders light surfaces in light mode', (
      tester,
    ) async {
      await pumpDatabaseTab(tester, buildAppTheme());
      final materials = tester.widgetList<Material>(find.byType(Material));
      expect(
        materials.any((m) => m.color == StrategyPalette.surface),
        isTrue,
        reason: 'the filter bar should sit on the light surface tone',
      );
      expect(
        materials.any((m) => m.color == StrategyPalette.darkSurface),
        isFalse,
        reason: 'no dark surface tone may leak into the light theme',
      );
    });

    testWidgets('palette accessors resolve dark tokens in dark mode', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkAppTheme(),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(StrategyPalette.surfaceOf(context), StrategyPalette.darkSurface);
      expect(
        StrategyPalette.surfaceStrongOf(context),
        StrategyPalette.darkSurfaceStrong,
      );
      expect(StrategyPalette.borderOf(context), StrategyPalette.darkOutline);
    });

    testWidgets('palette accessors resolve light tokens in light mode', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(StrategyPalette.surfaceOf(context), StrategyPalette.surface);
      expect(
        StrategyPalette.surfaceStrongOf(context),
        StrategyPalette.surfaceStrong,
      );
      expect(StrategyPalette.borderOf(context), StrategyPalette.border);
    });
  });
}
