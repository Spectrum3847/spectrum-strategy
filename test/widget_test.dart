import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_assignment_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_assignment_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/services/tour_service.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/ui/app_shell.dart';
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

class _FakeAssignmentSyncService implements ScoutAssignmentSyncService {
  @override
  Stream<List<ScoutAssignment>> watchAll() =>
      const Stream<List<ScoutAssignment>>.empty();

  @override
  Future<void> upsert(ScoutAssignment assignment) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dispose() async {}
}

class _RouteWatcher extends NavigatorObserver {
  final List<String> pushedPopupMenuRoutes = [];

  void _record(Route<dynamic>? route) {
    final name = route?.runtimeType.toString() ?? '';
    if (name.contains('PopupMenuRoute')) {
      pushedPopupMenuRoutes.add(name);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);
}

Future<AppShell> _buildShell(
  WidgetTester tester, {
  SpectrumUser? signedInUser,
  Set<UserRole>? userRoles,
  TourService? tourService,
  List<NavigatorObserver> navigatorObservers = const [],
}) async {
  final strategy = StrategyController(directory: FakeMatchDirectory());
  final scouting = ScoutingController(storage: FakeScoutingStorage());
  final cycleLog = CycleLogController(storage: FakeCycleLogStorage());
  final config = ScoutConfigController(service: FakeScoutConfigService());
  final auth = FakeSpectrumAuthService(initialUser: signedInUser);
  final theme = ThemeController();
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
  final assignment = ScoutAssignmentController(
    syncService: _FakeAssignmentSyncService(),
  );
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
    userRoleController: roles,
    eventController: event,
    assignmentController: assignment,
    pitScoutConfigController: pitScoutConfig,
    pitScoutingController: pitScouting,
    prescoutConfigController: prescoutConfig,
    prescoutingController: prescouting,
    postMatchReportController: postMatchReport,
    tourService: tourService,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      navigatorObservers: navigatorObservers,
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
    expect(find.byType(NavigationBar), findsNothing);

    expect(
      find.widgetWithText(FilledButton, 'Sign in with Google'),
      findsOneWidget,
    );
  });

  testWidgets('Strategy role shows four primary destinations', (tester) async {
    const user = SpectrumUser(uid: 'strat-uid', displayName: 'Strat');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.strategy},
    );

    expect(find.text('Spectrum Strategy'), findsOneWidget);

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    final navBar = find.byType(NavigationBar);
    expect(
      find.descendant(of: navBar, matching: find.text('Strategy')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Scout')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Prematch')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Database')),
      findsOneWidget,
    );

    expect(
      find.descendant(of: navBar, matching: find.text('Settings')),
      findsNothing,
    );
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byTooltip('Save image'), findsOneWidget);
    expect(find.byTooltip('Share image'), findsOneWidget);
    expect(find.byTooltip('Matches'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);
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

    await tester.tap(find.text('Scout'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Prematch'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Save image'), findsNothing);
    expect(find.byTooltip('Share image'), findsNothing);
    expect(find.byTooltip('Matches'), findsNothing);
    expect(find.byTooltip('Account'), findsOneWidget);

    expect(find.text('Pre-Scouting'), findsNothing);
  });

  testWidgets(
    'Selecting Settings via overflow hides Strategy-only AppBar actions',
    (tester) async {
      const user = SpectrumUser(uid: 'strat-uid4', displayName: 'Strat');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.strategy},
      );

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Save image'), findsNothing);
      expect(find.byTooltip('Share image'), findsNothing);
      expect(find.byTooltip('Matches'), findsNothing);
      expect(find.byTooltip('Account'), findsOneWidget);
    },
  );

  testWidgets('Scouter role shows no nav bar; everything else in overflow', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'scout-uid', displayName: 'Scout');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter},
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('More'), findsOneWidget);

    expect(find.byTooltip('Scout assignments'), findsOneWidget);
  });

  testWidgets('Scouter is never stranded on a secondary tab', (tester) async {
    const user = SpectrumUser(uid: 'scout-uid', displayName: 'Scout');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.scouter},
    );

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Scout assignments'), findsOneWidget);
  });

  testWidgets(
    'Admin role shows four primary destinations and overflow with Docs/Users/Settings',
    (tester) async {
      const user = SpectrumUser(uid: 'admin-uid', displayName: 'Admin');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.admin},
      );

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      final navBar = find.byType(NavigationBar);
      expect(
        find.descendant(of: navBar, matching: find.text('Strategy')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('Scout')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('Prematch')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('Database')),
        findsOneWidget,
      );

      expect(find.byTooltip('More'), findsOneWidget);
    },
  );

  testWidgets('Developer role shows four primary destinations and overflow', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'dev-uid', displayName: 'Developer');
    await _buildShell(
      tester,
      signedInUser: user,
      userRoles: {UserRole.developer},
    );

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    final navBar = find.byType(NavigationBar);
    expect(
      find.descendant(of: navBar, matching: find.text('Strategy')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Scout')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Prematch')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navBar, matching: find.text('Database')),
      findsOneWidget,
    );

    expect(find.byTooltip('More'), findsOneWidget);
  });

  testWidgets(
    'Secondary tab suppresses the nav bar selected indicator; primary restores it',
    (tester) async {
      const user = SpectrumUser(uid: 'strat-nav-uid', displayName: 'Strat');
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.strategy},
      );

      await tester.tap(find.text('Scout').first);
      await tester.pumpAndSettle();

      Color indicatorColor() {
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        return bar.indicatorColor ??
            NavigationBarTheme.of(tester.element(find.byType(NavigationBar)))
                .indicatorColor ??
            const Color(0xFF000000);
      }

      expect(indicatorColor(), isNot(Colors.transparent));

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();

      expect(indicatorColor(), Colors.transparent);

      await tester.tap(find.text('Strategy').first);
      await tester.pumpAndSettle();
      expect(indicatorColor(), isNot(Colors.transparent));
    },
  );

  testWidgets(
    'Multi-role scouter+admin sees four primary destinations and overflow',
    (tester) async {
      const user = SpectrumUser(
        uid: 'scout-admin-uid',
        displayName: 'ScoutAdmin',
      );
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.scouter, UserRole.admin},
      );

      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byTooltip('More'), findsOneWidget);
    },
  );

  testWidgets('New user auto-gets scouter and lands in the app', (
    tester,
  ) async {
    const user = SpectrumUser(uid: 'new-uid', displayName: 'New User');

    await _buildShell(tester, signedInUser: user);

    expect(find.text('No access'), findsNothing);

    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<int>, 'Database'), findsNothing);
  });

  testWidgets('Demoted viewer sees the no-access screen', (tester) async {
    const user = SpectrumUser(
      uid: 'demoted-uid',
      displayName: 'Demoted',
      email: 'demoted@example.org',
    );
    await _buildShell(tester, signedInUser: user, userRoles: {UserRole.viewer});

    expect(find.byType(NavigationBar), findsNothing);
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

    expect(find.widgetWithText(PopupMenuItem<int>, 'Database'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<int>, 'Prematch'), findsNothing);
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

      await tester.tap(find.text('Database'));
      await tester.pumpAndSettle();

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

    await tester.tap(find.text('Database'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to load the team database'), findsOneWidget);
  });

  testWidgets('Database tab filters stack on phone width without overflow', (
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

    await tester.tap(find.text('Database'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Filter by team'), findsOneWidget);
    expect(find.text('Filter by match'), findsOneWidget);

    final teamFilterRect = tester.getRect(find.text('Filter by team'));
    final matchFilterRect = tester.getRect(find.text('Filter by match'));
    expect(teamFilterRect.top, lessThan(matchFilterRect.top));

    await tester.tap(find.text('Filter by team'), warnIfMissed: false);
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

    await tester.tap(find.text('Database'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filter by match'), warnIfMissed: false);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text('Filter by match'), warnIfMissed: false);
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
    final scouter = buildTourSteps(const [1, 4, 6]);
    expect(scouter.map((s) => s.title), [
      'Welcome to Spectrum Strategy',
      'Scout',
      'Docs',
      'Settings',
    ]);

    final all = buildTourSteps(const [0, 1, 2, 3, 4, 5, 6]);
    expect(all.map((s) => s.title), [
      'Welcome to Spectrum Strategy',
      'Strategy',
      'Scout',
      'Prematch',
      'Database',
      'Docs',
      'Users',
      'Settings',
    ]);
  });

  testWidgets(
    'Welcome tour rapid Back/Next across the primary/secondary boundary '
    'never pushes a PopupMenuRoute',
    (tester) async {
      const user = SpectrumUser(uid: 'scouter-tour', displayName: 'Scouter');
      final tour = FakeTourService();
      final routes = _RouteWatcher();
      await _buildShell(
        tester,
        signedInUser: user,
        userRoles: {UserRole.scouter},
        tourService: tour,
        navigatorObservers: [routes],
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
      await back();
      await next();
      await next();
      await back();
      await back();
      await next();
      await next();
      await next();

      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Spectrum Strategy'), findsNothing);
      expect(tour.seen, isTrue);

      expect(routes.pushedPopupMenuRoutes, isEmpty);
    },
  );
}
