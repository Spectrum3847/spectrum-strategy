import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/app.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_assignment_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_assignment_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_shift_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/shift_trade_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/event_sections_controller.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';

import 'support/fake_cycle_log_storage.dart';
import 'support/fake_match_directory.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';
import 'support/fake_prescout_config_service.dart';
import 'support/fake_prescouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scout_shift_sync_service.dart';
import 'support/fake_shift_trade_sync_service.dart';
import 'support/fake_scouting_storage.dart';
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

class _SlowAuthService implements SpectrumAuthService {
  final Completer<void> _initGate = Completer<void>();
  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();
  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.unknown,
  );

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  @override
  Future<String?> idToken() async => null;

  @override
  Future<void> initialize() async {
    await _initGate.future;
    _emit(
      const SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: SpectrumUser(uid: 'uid-1', displayName: 'Dana Strategist'),
      ),
    );
  }

  void resolve() {
    if (!_initGate.isCompleted) _initGate.complete();
  }

  @override
  Future<void> signIn() async {}

  @override
  Future<void> updateDisplayName(String displayName) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}

class _ThrowingInitGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> init(InitParameters params) async {
    throw const GoogleSignInException(
      code: GoogleSignInExceptionCode.unknownError,
    );
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async => null;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async => throw StateError('not reached in this test');

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

Widget _buildApp(SpectrumAuthService auth, UserRoleController roleController) {
  return StrategyApp(
    strategyController: StrategyController(directory: FakeMatchDirectory()),
    scoutingController: ScoutingController(storage: FakeScoutingStorage()),
    configController: ScoutConfigController(service: FakeScoutConfigService()),
    authService: auth,
    themeController: ThemeController(),
    userRoleController: roleController,
    eventController: EventController(),
    pickListController: PickListController(),
    eventStatsController: EventStatsController(tbaClient: null),
    eventSectionsController: EventSectionsController(tbaClient: null),
    assignmentController: ScoutAssignmentController(
      syncService: _FakeAssignmentSyncService(),
    ),
    pitScoutConfigController: PitScoutConfigController(
      service: FakePitScoutConfigService(),
    ),
    pitScoutingController: PitScoutingController(
      storage: FakePitScoutingStorage(),
    ),
    prescoutConfigController: PrescoutConfigController(
      service: FakePrescoutConfigService(),
    ),
    prescoutingController: PrescoutingController(
      storage: FakePrescoutingStorage(),
    ),
    cycleLogController: CycleLogController(storage: FakeCycleLogStorage()),
    playoffBoardController: PlayoffBoardController(
      storage: FakePlayoffBoardStorage(),
    ),
    postMatchReportController: PostMatchReportController(
      storage: FakePostMatchReportStorage(),
      syncService: FakePostMatchReportSyncService(),
    ),
    shiftController: ScoutShiftController(
      syncService: FakeScoutShiftSyncService(),
    ),
    shiftTradeController: ShiftTradeController(
      syncService: FakeShiftTradeSyncService(),
    ),
  );
}

void main() {
  testWidgets(
    'the first frame renders without waiting on auth, and does not flash '
    'the sign-in screen at an already-signed-in user',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final auth = _SlowAuthService();
      final roleService = FakeUserRoleService();
      roleService.setRoles('uid-1', {UserRole.strategy});
      final roleController = UserRoleController(
        authService: auth,
        roleService: roleService,
      );

      await tester.pumpWidget(_buildApp(auth, roleController));

      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(find.text('Spectrum Strategy could not start'), findsNothing);

      expect(find.text('You do not have access.'), findsNothing);
      expect(find.text('Sign in with Google'), findsNothing);

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      auth.resolve();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('You do not have access.'), findsNothing);
    },
  );

  testWidgets('a throwing initialize() leaves the app actionable, not spinning '
      'forever', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final originalPlatform = GoogleSignInPlatform.instance;
    GoogleSignInPlatform.instance = _ThrowingInitGoogleSignInPlatform();
    addTearDown(() => GoogleSignInPlatform.instance = originalPlatform);

    final auth = FirebaseSpectrumAuthService(
      appAuth: MockFirebaseAuth(),
      googleSignIn: GoogleSignIn.instance,
    );
    final roleController = UserRoleController(
      authService: auth,
      roleService: FakeUserRoleService(),
    );

    await tester.pumpWidget(_buildApp(auth, roleController));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
