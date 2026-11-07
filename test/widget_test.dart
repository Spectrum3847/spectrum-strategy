import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass/liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/services/tour_service.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/ui/app_shell.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/ui/now_tab.dart';
import 'package:spectrumstrategy/src/ui/welcome_tour.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_cycle_log_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';
import 'support/fake_prescout_config_service.dart';
import 'support/fake_prescouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_tour_service.dart';
import 'support/fake_user_role_service.dart';
import 'support/fake_playoff_board_storage.dart';

List<String> _railLabels(WidgetTester tester) {
  final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
  return [for (final d in rail.destinations) (d.label as Text).data!];
}

int? _railSelected(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex;

List<String> _barLabels(WidgetTester tester) {
  final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
  final destinations = bar.destinations.cast<NavigationDestination>();
  return [for (final d in destinations) d.label];
}

List<String> _moreSheetLabels(WidgetTester tester) {
  final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
  return [for (final t in tiles) (t.title! as Text).data!];
}

Future<void> _openMore(WidgetTester tester) async {
  final more = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text('More'),
  );
  await tester.tap(more);
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final hasRail = find.byType(NavigationRail).evaluate().isNotEmpty;
  final nav = find.byType(hasRail ? NavigationRail : NavigationBar);
  final inNav = find.descendant(of: nav, matching: find.text(label));
  if (inNav.evaluate().isEmpty) {
    await _openMore(tester);
    await tester.tap(find.widgetWithText(ListTile, label));
  } else {
    await tester.ensureVisible(inNav.first);
    await tester.tap(inNav.first);
  }
  await tester.pumpAndSettle();
}

void _setWindow(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<AppShell> _buildShell(
  WidgetTester tester, {
  SpectrumUser? signedInUser,
  Set<UserRole>? userRoles,
  TourService? tourService,
  bool? liquidGlassSupported,
  ThemeMode themeMode = ThemeMode.light,
  ThemeController? themeController,
}) async {
  final strategy = StrategyController(directory: FakeMatchDirectory());
  final scouting = ScoutingController(storage: FakeScoutingStorage());
  final cycleLog = CycleLogController(storage: FakeCycleLogStorage());
  final config = ScoutConfigController(service: FakeScoutConfigService());
  final auth = FakeSpectrumAuthService(initialUser: signedInUser);
  final theme = themeController ?? ThemeController();
  final roleService = FakeUserRoleService();
  if (signedInUser != null && userRoles != null) {
    roleService.setRoles(signedInUser.uid, userRoles);
  }
  final roles = UserRoleController(authService: auth, roleService: roleService);
  final event = EventController();
  final pitScoutConfig = PitScoutConfigController(
    service: FakePitScoutConfigService(),
  );
  final pitScouting = PitScoutingController(storage: FakePitScoutingStorage());
  final prescoutConfig = PrescoutConfigController(
    service: FakePrescoutConfigService(),
  );
  final prescouting = PrescoutingController(storage: FakePrescoutingStorage());
  final postMatchReport = PostMatchReportController(
    storage: FakePostMatchReportStorage(),
    syncService: FakePostMatchReportSyncService(),
  );

  await Future.wait(<Future<void>>[
    strategy.bootstrap(),
    scouting.bootstrap(),
    cycleLog.bootstrap(),
    config.bootstrap(),
    roles.bootstrap(),
    pitScoutConfig.bootstrap(),
    pitScouting.bootstrap(),
    prescoutConfig.bootstrap(),
    prescouting.bootstrap(),
    postMatchReport.bootstrap(),
  ]);

  final shell = AppShell(
    strategyController: strategy,
    scoutingController: scouting,
    cycleLogController: cycleLog,
    playoffBoardController: PlayoffBoardController(
      storage: FakePlayoffBoardStorage(),
    ),
    configController: config,
    authService: auth,
    themeController: theme,
    debugLiquidGlassSupported: liquidGlassSupported,
    userRoleController: roles,
    eventController: event,
    pitScoutConfigController: pitScoutConfig,
    pitScoutingController: pitScouting,
    prescoutConfigController: prescoutConfig,
    prescoutingController: prescouting,
    postMatchReportController: postMatchReport,
    tourService: tourService,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        splashFactory: NoSplash.splashFactory,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        splashFactory: NoSplash.splashFactory,
      ),
      themeMode: themeMode,
      home: shell,
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  testWidgets('Viewer role (no user signed in) shows no-access screen', (
    tester,
  ) async {
    await _buildShell(tester);

    expect(find.text('Spectrum Strategy'), findsOneWidget);
    expect(find.text('You are signed out.'), findsOneWidget);

    expect(
      find.widgetWithText(FilledButton, 'Sign in with Google'),
      findsOneWidget,
    );
  });

  testWidgets('glass chrome stays off where the platform cannot draw it', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    final shell = await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    unawaited(shell.themeController.setLiquidGlass(true));
    await tester.pump();

    expect(shell.themeController.liquidGlass, isTrue);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.appBar, isA<AppBar>());
  });

  testWidgets('glass never extends the body behind the chrome', (tester) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    final shell = await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
      liquidGlassSupported: true,
    );

    unawaited(shell.themeController.setLiquidGlass(true));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);

    expect(scaffold.extendBody, isFalse);

    expect(scaffold.extendBodyBehindAppBar, isFalse);

    expect(
      GlassChrome.bottomInsetOf(tester.element(find.byType(Scaffold).first)),
      MediaQuery.paddingOf(tester.element(find.byType(Scaffold).first)).bottom,
    );
  });

  testWidgets(
    'the glass More sheet carries the app theme brightness, not the system '
    'default',
    (tester) async {
      _setWindow(tester, 390, 844);
      const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
      final shell = await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.strategy},
        liquidGlassSupported: true,
        themeMode: ThemeMode.dark,
      );
      unawaited(shell.themeController.setLiquidGlass(true));
      await tester.pumpAndSettle();

      await _openMore(tester);

      final glassWidgets = tester.widgetList<LiquidGlass>(
        find.byType(LiquidGlass),
      );
      expect(glassWidgets, isNotEmpty);
      for (final glass in glassWidgets) {
        expect(glass.brightness, Brightness.dark);
      }
    },
  );

  testWidgets('the body is never extended when glass is off', (tester) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    final shell = await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    unawaited(shell.themeController.setLiquidGlass(true));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isFalse);
    expect(scaffold.extendBodyBehindAppBar, isFalse);
  });

  testWidgets('Strategy role lists every tab in the rail, primary first', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    expect(find.text('Spectrum Strategy'), findsOneWidget);

    expect(find.byType(NavigationBar), findsNothing);

    expect(_railLabels(tester), [
      'Now',
      'Strategy',
      'Scout',
      'Prematch',
      'Database',
      'Docs',
      'Schedule',
      'Settings',
    ]);

    expect(find.byTooltip('Save image'), findsNothing);
    expect(find.byTooltip('Find team'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);

    await _openTab(tester, 'Strategy');

    expect(find.byTooltip('Save image'), findsOneWidget);
    expect(find.byTooltip('Share image'), findsOneWidget);
    expect(find.byTooltip('Matches'), findsOneWidget);
    expect(find.byTooltip('Find team'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);
  });

  testWidgets('The shell opens on the Now tab', (tester) async {
    const user = SpectrumUser(uid: 'strat-now', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    expect(_railSelected(tester), 0);
    expect(find.byType(NowTab), findsOneWidget);

    expect(find.textContaining('No event selected'), findsOneWidget);
  });

  testWidgets('Find team opens that team page', (tester) async {
    const user = SpectrumUser(uid: 'strat-find', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await tester.tap(find.byTooltip('Find team'));
    await tester.pumpAndSettle();
    expect(find.text('Go to team or match'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(find.text('Go to team or match'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Team 3847'), findsOneWidget);
  });

  testWidgets('Selecting Scout tab hides Strategy-only AppBar actions', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'strat-uid2', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await _openTab(tester, 'Scout');

    expect(find.byTooltip('Save image'), findsNothing);
    expect(find.byTooltip('Share image'), findsNothing);
    expect(find.byTooltip('Matches'), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Scout shifts'), findsOneWidget);

    expect(find.text('Pre-Scouting'), findsOneWidget);
  });

  testWidgets('Selecting Prematch tab hides Strategy-only AppBar actions', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'strat-uid3', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await _openTab(tester, 'Prematch');

    expect(find.byTooltip('Save image'), findsNothing);
    expect(find.byTooltip('Share image'), findsNothing);
    expect(find.byTooltip('Matches'), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);

    expect(find.text('Pre-Scouting'), findsNothing);
  });

  testWidgets(
    'Selecting Settings from the navigation hides Strategy-only AppBar '
    'actions',
    (tester) async {
      const user = SpectrumUser(uid: 'strat-uid4', displayName: 'Strat');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.strategy},
      );

      await _openTab(tester, 'Settings');

      expect(find.byTooltip('Save image'), findsNothing);
      expect(find.byTooltip('Share image'), findsNothing);
      expect(find.byTooltip('Matches'), findsNothing);
      expect(find.byTooltip('Account'), findsOneWidget);
    },
  );

  testWidgets('Scouter role lists only the tabs the role grants', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'scout-uid', displayName: 'Scout');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter},
    );

    expect(_railLabels(tester), [
      'Now',
      'Scout',
      'Docs',
      'Schedule',
      'Settings',
    ]);
  });

  testWidgets('Every tab is one tap from every other', (tester) async {
    const user = SpectrumUser(uid: 'scout-uid', displayName: 'Scout');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter},
    );

    await _openTab(tester, 'Settings');
    expect(find.byTooltip('Scout shifts'), findsNothing);

    await _openTab(tester, 'Scout');
    expect(find.byTooltip('Scout shifts'), findsOneWidget);
  });

  testWidgets('Admin role lists the admin-only Users tab too', (tester) async {
    const user = SpectrumUser(uid: 'admin-uid', displayName: 'Admin');
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.admin});

    expect(_railLabels(tester), [
      'Now',
      'Strategy',
      'Scout',
      'Prematch',
      'Database',
      'Docs',
      'Schedule',
      'Users',
      'Settings',
    ]);
  });

  testWidgets('Developer role lists the developer-only Usage tab too', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'dev-uid', displayName: 'Developer');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.developer},
    );

    expect(_railLabels(tester), [
      'Now',
      'Strategy',
      'Scout',
      'Prematch',
      'Database',
      'Docs',
      'Schedule',
      'Usage',
      'Settings',
    ]);
  });

  testWidgets('Multi-role scouter+admin sees the union of both roles\' tabs', (
    tester,
  ) async {
    const user = SpectrumUser(
      uid: 'scout-admin-uid',
      displayName: 'ScoutAdmin',
    );
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter, UserRole.admin},
    );

    expect(_railLabels(tester), [
      'Now',
      'Strategy',
      'Scout',
      'Prematch',
      'Database',
      'Docs',
      'Schedule',
      'Users',
      'Settings',
    ]);
  });

  testWidgets('New user auto-gets scouter and lands in the app', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'new-uid', displayName: 'New User');

    await _buildShell(tester, signedInUser: user);

    expect(find.text('No access'), findsNothing);

    expect(_railLabels(tester), [
      'Now',
      'Scout',
      'Docs',
      'Schedule',
      'Settings',
    ]);
  });

  testWidgets('Demoted viewer sees the no-access screen', (tester) async {
    const user = SpectrumUser(
      uid: 'demoted-uid',
      displayName: 'Demoted',
      email: 'demoted@example.org',
    );
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.viewer});

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('No access'), findsOneWidget);

    expect(
      find.textContaining('You are signed in as demoted@example.org.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ask an admin to set your roles'),
      findsOneWidget,
    );

    expect(
      find.widgetWithText(FilledButton, 'Sign in with Google'),
      findsNothing,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Switch account'),
      findsOneWidget,
    );
  });

  testWidgets('Scouter does not see the Database tab', (tester) async {
    const user = SpectrumUser(uid: 'scout-only', displayName: 'Scout');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter},
    );

    expect(_railLabels(tester), isNot(contains('Database')));
    expect(_railLabels(tester), isNot(contains('Prematch')));
  });

  testWidgets(
    'Database tab is visible and shows empty state for strategy role',
    (tester) async {
      const user = SpectrumUser(uid: 'strat-db', displayName: 'Strat');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.strategy},
      );

      await _openTab(tester, 'Database');

      expect(find.byTooltip('Refresh from database'), findsOneWidget);
      expect(find.text('Filter by team'), findsOneWidget);
      expect(find.text('Filter by match'), findsOneWidget);
    },
  );

  testWidgets('the match picker header does not overflow at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const user = SpectrumUser(uid: 'strat-picker-narrow', displayName: 'S');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await _openTab(tester, 'Strategy');
    await tester.tap(find.byTooltip('Matches'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final close = tester.getRect(find.byTooltip('Close'));
    expect(close.right, lessThanOrEqualTo(390.0));
  });

  testWidgets('Database tab sync status row does not overflow at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const user = SpectrumUser(uid: 'strat-db-phone', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await _openTab(tester, 'Database');

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to load the team database'), findsOneWidget);
  });

  testWidgets('Database tab collapses to one filter row on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const user = SpectrumUser(uid: 'strat-db-phone', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await _openTab(tester, 'Database');

    expect(tester.takeException(), isNull);
    expect(find.text('Filter by team'), findsNothing);
    expect(find.text('Filter by match'), findsNothing);
    expect(find.text('Team or q42'), findsOneWidget);

    await tester.tap(find.text('Team or q42'), warnIfMissed: false);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('Database tab filter field clears focus on submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const user = SpectrumUser(uid: 'strat-db-submit', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    await _openTab(tester, 'Database');

    await tester.tap(find.text('Team or q42'), warnIfMissed: false);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text('Team or q42'), warnIfMissed: false);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('First launch shows the welcome tour; Skip persists', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    final tour = FakeTourService();
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
      tourService: tour,
    );

    expect(find.text('Welcome to Spectrum Strategy'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Spectrum Strategy'), findsNothing);
    expect(tour.seen, isTrue);
  });

  testWidgets('Welcome tour does not show once seen', (tester) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
      tourService: FakeTourService(seen: true),
    );

    expect(find.text('Welcome to Spectrum Strategy'), findsNothing);
  });

  testWidgets('Viewer never sees the welcome tour', (tester) async {
    await _buildShell(tester, tourService: FakeTourService());

    expect(find.text('You are signed out.'), findsOneWidget);
    expect(find.text('Welcome to Spectrum Strategy'), findsNothing);
  });

  testWidgets('Welcome tour steps follow the visible tabs', (tester) async {
    final scouter = buildTourSteps(const [10, 1, 4, 6]);
    expect(scouter.map((s) => s.title), [
      'Welcome to Spectrum Strategy',
      'Now',
      'Scout',
      'Docs',
      'Settings',
    ]);

    final all = buildTourSteps(const [10, 0, 1, 2, 3, 4, 5, 6]);
    expect(all.map((s) => s.title), [
      'Welcome to Spectrum Strategy',
      'Now',
      'Strategy',
      'Scout',
      'Prematch',
      'Database',
      'Docs',
      'Users',
      'Settings',
    ]);
  });

  testWidgets('Welcome tour walks every step back and forth, then finishes', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'scouter-tour', displayName: 'Scouter');
    final tour = FakeTourService();
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter},
      tourService: tour,
    );

    expect(find.text('Welcome to Spectrum Strategy'), findsOneWidget);

    Future<void> next() async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
    }

    await next();
    await next();
    await next();
    await back();
    await next();
    await next();
    await back();
    await back();
    await next();
    await next();
    await next();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Spectrum Strategy'), findsNothing);
    expect(tour.seen, isTrue);
  });

  testWidgets('Welcome tour card stays clear of the bottom bar on a phone', (
    tester,
  ) async {
    _setWindow(tester, 390, 844);
    const user = SpectrumUser(uid: 'strat-tour-phone', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
      tourService: FakeTourService(),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
    final cardBottom = tester.getBottomLeft(find.byType(PageView)).dy;
    expect(cardBottom, lessThanOrEqualTo(barTop));
  });

  testWidgets('Welcome tour card stays clear of the rail on a tablet', (
    tester,
  ) async {
    _setWindow(tester, 600, 900);
    const user = SpectrumUser(uid: 'strat-tour-tablet', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
      tourService: FakeTourService(),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final railRight = tester.getTopRight(find.byType(NavigationRail)).dx;
    final cardLeft = tester.getTopLeft(find.byType(PageView)).dx;
    expect(cardLeft, greaterThanOrEqualTo(railRight));
  });

  group('adaptive navigation', () {
    const strategist = SpectrumUser(uid: 'nav-strat', displayName: 'Strat');

    testWidgets('phone: bottom bar with the primary tabs and More', (
      tester,
    ) async {
      _setWindow(tester, 390, 844);
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
      );

      expect(find.byType(NavigationRail), findsNothing);
      expect(_barLabels(tester), [
        'Now',
        'Strategy',
        'Scout',
        'Prematch',
        'More',
      ]);
      expect(tester.takeException(), isNull);

      await _openMore(tester);
      expect(_moreSheetLabels(tester), [
        'Database',
        'Docs',
        'Schedule',
        'Settings',
      ]);

      await tester.tap(find.widgetWithText(ListTile, 'Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
      expect(find.byTooltip('Save image'), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 4);
    });

    testWidgets('phone: tapping a bar destination switches tabs', (
      tester,
    ) async {
      _setWindow(tester, 390, 844);
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
      );

      expect(find.byTooltip('Save image'), findsNothing);

      await _openTab(tester, 'Strategy');

      expect(find.byTooltip('Save image'), findsOneWidget);

      await _openTab(tester, 'Scout');

      expect(find.byTooltip('Save image'), findsNothing);
      expect(find.byTooltip('Scout shifts'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 2);
    });

    testWidgets('phone: a scouter gets Now, Scout and More', (tester) async {
      _setWindow(tester, 390, 844);
      await _buildShell(
        tester,
        signedInUser: const SpectrumUser(uid: 'nav-scout', displayName: 'S'),
        userRoles: {UserRole.scouter},
      );

      expect(_barLabels(tester), ['Now', 'Scout', 'More']);

      await _openMore(tester);
      expect(_moreSheetLabels(tester), ['Docs', 'Schedule', 'Settings']);
    });

    testWidgets('tablet: a labelled rail holds every tab', (tester) async {
      _setWindow(tester, 800, 1000);
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
      );

      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(rail.labelType, NavigationRailLabelType.all);
      expect(_railLabels(tester), [
        'Now',
        'Strategy',
        'Scout',
        'Prematch',
        'Database',
        'Docs',
        'Schedule',
        'Settings',
      ]);

      await _openTab(tester, 'Scout');

      expect(find.byTooltip('Scout shifts'), findsOneWidget);
      expect(_railSelected(tester), 2);
    });

    testWidgets('desktop: the rail extends into a sidebar', (tester) async {
      _setWindow(tester, 1280, 800);
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
      );

      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);

      await _openTab(tester, 'Settings');

      expect(find.byTooltip('Save image'), findsNothing);
      expect(_railSelected(tester), 7);
    });

    testWidgets('desktop: the toggle collapses and expands the sidebar', (
      tester,
    ) async {
      _setWindow(tester, 1280, 800);
      final theme = ThemeController();
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
        themeController: theme,
      );
      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));

      expect(rail().extended, isTrue);

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();

      expect(theme.sidebarExpanded, isFalse);
      expect(rail().extended, isFalse);
      expect(rail().labelType, NavigationRailLabelType.all);
      expect(find.byTooltip('Collapse sidebar'), findsNothing);

      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pumpAndSettle();

      expect(theme.sidebarExpanded, isTrue);
      expect(rail().extended, isTrue);
    });

    testWidgets('desktop: a stored collapsed choice starts compact', (
      tester,
    ) async {
      _setWindow(tester, 1280, 800);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_sidebar_expanded': false,
      });
      final theme = ThemeController();
      await theme.bootstrap();
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
        themeController: theme,
      );

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(find.byTooltip('Expand sidebar'), findsOneWidget);
    });

    testWidgets('only the desktop width has a sidebar toggle', (tester) async {
      for (final width in [390.0, 800.0]) {
        _setWindow(tester, width, 900);
        await _buildShell(
          tester,
          signedInUser: strategist,
          userRoles: {UserRole.strategy},
        );

        expect(find.byTooltip('Collapse sidebar'), findsNothing);
        expect(find.byTooltip('Expand sidebar'), findsNothing);
      }
    });

    testWidgets('resizing keeps the open tab', (tester) async {
      _setWindow(tester, 390, 844);
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
      );
      await _openTab(tester, 'Scout');

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Scout shifts'), findsOneWidget);
      expect(_railSelected(tester), 2);
    });

    testWidgets('switching tabs does not rebuild the other tabs', (
      tester,
    ) async {
      _setWindow(tester, 390, 844);
      await _buildShell(
        tester,
        signedInUser: strategist,
        userRoles: {UserRole.strategy},
      );
      NowTab nowTab() =>
          tester.widget<NowTab>(find.byType(NowTab, skipOffstage: false));
      final before = nowTab();

      await _openTab(tester, 'Scout');

      expect(identical(nowTab(), before), isTrue);
    });
  });
}
