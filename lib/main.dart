import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart'
    show
        LicenseEntryWithLineBreaks,
        LicenseRegistry,
        debugPrint,
        defaultTargetPlatform,
        kIsWeb,
        TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'firebase_options_central.dart';
import 'src/app.dart';
import 'src/services/central_auth_client.dart';
import 'src/services/central_rest_auth_client.dart';
import 'src/services/desktop_active_event_sync_service.dart';
import 'src/services/desktop_auth_service.dart';
import 'src/services/desktop_firestore_cache_stub.dart'
    if (dart.library.io) 'src/services/desktop_firestore_cache_io.dart'
    as firestore_cache_factory;
import 'src/services/desktop_user_role_service.dart';
import 'src/services/match_directory.dart';
import 'src/services/firestore_active_event_service.dart';
import 'src/services/local_only_services.dart';
import 'src/services/desktop_post_match_report_sync_service.dart';
import 'src/services/post_match_report_storage.dart';
import 'src/services/post_match_report_sync_service.dart';
import 'src/state/post_match_report_controller.dart';

import 'package:tba_client/tba_client.dart';

import 'src/scouting/services/accuracy_alert_service.dart';
import 'src/scouting/services/desktop_accuracy_alert_service.dart';
import 'src/scouting/services/desktop_pit_scouting_sync_service.dart';
import 'src/scouting/services/desktop_prescouting_sync_service.dart';
import 'src/scouting/services/desktop_scout_config_sync_service.dart';
import 'src/scouting/services/desktop_scout_assignment_sync_service.dart';
import 'src/scouting/services/desktop_scout_shift_sync_service.dart';
import 'src/scouting/services/desktop_scouting_sync_service.dart';
import 'src/scouting/services/firestore_scout_config_service.dart';
import 'src/scouting/services/pit_scouting_sync_service.dart';
import 'src/scouting/services/prescouting_sync_service.dart';
import 'src/scouting/services/scout_assignment_sync_service.dart';
import 'src/scouting/services/scout_shift_sync_service.dart';
import 'src/scouting/services/desktop_shift_trade_sync_service.dart';
import 'src/scouting/services/shift_trade_sync_service.dart';
import 'src/scouting/services/scouting_sync_service.dart';
import 'src/scouting/state/pit_scout_config_controller.dart';
import 'src/scouting/state/pit_scouting_controller.dart';
import 'src/scouting/state/prescout_config_controller.dart';
import 'src/scouting/state/prescouting_controller.dart';
import 'src/scouting/state/scout_assignment_controller.dart';
import 'src/scouting/state/scout_config_controller.dart';
import 'src/scouting/state/scout_shift_controller.dart';
import 'src/scouting/state/shift_trade_controller.dart';
import 'src/scouting/state/scouting_controller.dart';
import 'src/scouting/services/pit_photo_store_stub.dart'
    if (dart.library.io) 'src/scouting/services/pit_photo_store_io.dart'
    as pit_photo_store_factory;
import 'src/scouting/services/photo_worker_config.dart';
import 'src/scouting/services/pit_photo_upload_service.dart';
import 'src/scouting/services/pit_scouting_storage.dart';
import 'src/scouting/services/prescouting_storage.dart';
import 'src/scouting/services/scouting_storage.dart';
import 'src/services/desktop_pick_list_sync_service.dart';
import 'src/services/desktop_strategy_board_sync_service.dart';
import 'src/services/desktop_trait_table_sync_service.dart';
import 'src/services/trait_table_sync_service.dart';
import 'src/services/desktop_trex_assignments_sync_service.dart';
import 'src/services/trex_assignments_sync_service.dart';
import 'src/services/desktop_trex_team_list_sync_service.dart';
import 'src/services/trex_team_list_sync_service.dart';
import 'src/services/desktop_trex_trait_report_sync_service.dart';
import 'src/services/trex_trait_report_storage.dart';
import 'src/services/trex_trait_report_sync_service.dart';
import 'src/services/field_map_catalog.dart';
import 'src/services/issue_report_service.dart';
import 'src/services/pick_list_storage.dart';
import 'src/services/telemetry_service.dart';
import 'src/services/http_timeout_client.dart';

import 'package:statbotics_client/statbotics_client.dart';

import 'src/services/pick_list_sync_service.dart';
import 'src/services/strategy_board_sync_service.dart';
import 'src/services/spectrum_auth_service.dart';
import 'src/services/assistant/assistant_cache.dart';
import 'src/services/assistant/assistant_service.dart';
import 'src/services/assistant/firestore_assistant_config.dart';
import 'src/services/assistant/local_assistant_backend.dart';
import 'src/services/assistant/desktop_remote_assistant_cache.dart';
import 'src/services/assistant/firestore_remote_assistant_cache.dart';
import 'src/services/assistant/openrouter_assistant_backend.dart';
import 'src/services/assistant/remote_assistant_cache.dart';
import 'src/services/statbotics/team_history_service.dart';
import 'src/services/tba/firestore_tba_config.dart';
import 'src/services/tour_service.dart';
import 'src/services/team_avatar_service.dart';
import 'src/services/user_role_service.dart';
import 'src/services/web_auth_domain.dart';
import 'src/services/playoff_board_storage.dart';
import 'src/state/cycle_log_controller.dart';
import 'src/state/event_controller.dart';
import 'src/state/playoff_board_controller.dart';
import 'src/state/event_sections_controller.dart';
import 'src/state/event_stats_controller.dart';
import 'src/state/pick_list_controller.dart';
import 'src/state/strategy_controller.dart';
import 'src/state/trait_table_controller.dart';
import 'src/state/trex_assignments_controller.dart';
import 'src/state/trex_team_list_controller.dart';
import 'src/state/trex_trait_report_controller.dart';
import 'src/state/theme_controller.dart';
import 'src/state/user_role_controller.dart';

const String _oauthClientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

const String _oauthClientSecret = String.fromEnvironment(
  'GOOGLE_OAUTH_CLIENT_SECRET',
);

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(<String>['Overpass'], license);
  });

  var firebaseReady = false;

  FirebaseApp? centralApp;
  try {
    final options = kIsWeb
        ? webFirebaseOptionsForHost(
            Uri.base.host,
            DefaultFirebaseOptions.currentPlatform,
          )
        : DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    firebaseReady = true;
  } catch (error) {
    debugPrint('Firebase unavailable: $error');
  }

  if (firebaseReady && kIsWeb) {
    try {
      centralApp = await Firebase.initializeApp(
        name: 'central',
        options: centralFirebaseOptions(),
      );
    } catch (error) {
      debugPrint('Central platform unavailable: $error');
    }
  }

  final SpectrumAuthService authService;
  final UserRoleService roleService;
  ScoutingSyncService? scoutingSyncService;
  AccuracyAlertService? alertService;
  ScoutConfigSyncService? scoutConfigSyncService;

  ScoutConfigSyncService? pitScoutConfigSyncService;

  ScoutConfigSyncService? prescoutConfigSyncService;
  PickListSyncService? pickListSyncService;
  StrategyBoardSyncService? strategyBoardSyncService;
  PitScoutingSyncService? pitScoutingSyncService;
  PrescoutingSyncService? prescoutingSyncService;
  ScoutAssignmentSyncService? assignmentSyncService;
  TraitTableSyncService? traitTableSyncService;
  TRexAssignmentsSyncService? trexAssignmentsSyncService;
  TRexTeamListSyncService? trexTeamListSyncService;
  TrexTraitReportSyncService? trexTraitReportSyncService;

  PostMatchReportSyncService? postMatchReportSyncService;

  PostMatchReportStorage? desktopPostMatchReportStorage;
  ScoutShiftSyncService? shiftSyncService;
  ShiftTradeSyncService? shiftTradeSyncService;
  FirestoreTbaConfig? teamTbaConfig;

  FirestoreAssistantConfig? assistantConfig;

  RemoteAssistantCache? remoteAssistantCache;
  IssueReportService? issueReportService;

  Future<String?> Function()? photoWorkerFetcher;
  TelemetryService? telemetryService;
  ActiveEventSyncService? activeEventSyncService;

  ScoutingStorage? desktopScoutingStorage;
  PitScoutingStorage? desktopPitScoutingStorage;
  TrexTraitReportStorage? desktopTrexTraitReportStorage;
  PrescoutingStorage? desktopPrescoutingStorage;
  PickListStorage? desktopPickListStorage;

  final matchDirectory = SharedPreferencesMatchDirectory();

  if (firebaseReady && !_isDesktop) {
    if (kIsWeb) {
      final centralAuth = centralApp == null
          ? null
          : FirebaseAuth.instanceFor(app: centralApp);
      final centralClient = centralApp == null
          ? null
          : FirebaseCentralAuthClient(centralApp: centralApp);
      authService = FirebaseSpectrumAuthService(
        centralAuth: centralAuth,
        centralClient: centralClient,
      );
    } else {
      authService = FirebaseSpectrumAuthService(
        centralRest: CentralRestAuthClient(
          centralApiKey: centralFirebaseOptions().apiKey,
        ),
      );
    }
    roleService = FirestoreUserRoleService();
    scoutingSyncService = FirestoreScoutingSyncService(
      authService: authService,
    );
    alertService = FirestoreAccuracyAlertService(authService: authService);
    scoutConfigSyncService = FirestoreScoutConfigSyncService(
      authService: authService,
    );
    pitScoutConfigSyncService = FirestoreScoutConfigSyncService.pit(
      authService: authService,
    );
    prescoutConfigSyncService = FirestoreScoutConfigSyncService.prescout(
      authService: authService,
    );
    pickListSyncService = FirestorePickListSyncService(
      authService: authService,
    );
    strategyBoardSyncService = FirestoreStrategyBoardSyncService(
      authService: authService,
    );
    pitScoutingSyncService = FirestorePitScoutingSyncService(
      authService: authService,
    );
    prescoutingSyncService = FirestorePrescoutingSyncService(
      authService: authService,
    );
    assignmentSyncService = FirestoreScoutAssignmentSyncService(
      authService: authService,
    );
    traitTableSyncService = FirestoreTraitTableSyncService(
      authService: authService,
    );
    trexAssignmentsSyncService = FirestoreTRexAssignmentsSyncService(
      authService: authService,
    );
    trexTeamListSyncService = FirestoreTRexTeamListSyncService(
      authService: authService,
    );
    trexTraitReportSyncService = FirestoreTrexTraitReportSyncService(
      authService: authService,
    );
    postMatchReportSyncService = FirestorePostMatchReportSyncService(
      authService: authService,
    );
    shiftSyncService = FirestoreScoutShiftSyncService(authService: authService);
    shiftTradeSyncService = FirestoreShiftTradeSyncService(
      authService: authService,
    );

    teamTbaConfig = FirestoreTbaConfig();
    assistantConfig = FirestoreAssistantConfig();
    remoteAssistantCache = FirestoreRemoteAssistantCache(
      authService: authService,
    );
    telemetryService = TelemetryService();
    activeEventSyncService = FirestoreActiveEventSyncService(
      authService: authService,
    );
  } else if (_isDesktop && _oauthClientId.isNotEmpty) {
    final desktopAuth = DesktopAuthService(
      clientId: _oauthClientId,
      clientSecret: _oauthClientSecret,
      firebaseApiKey: DefaultFirebaseOptions.web.apiKey,

      centralApiKey: centralFirebaseOptions().apiKey,
      launch: (url) => launchUrl(url, mode: LaunchMode.externalApplication),

      session: fc.FirebaseAuthSession(
        apiKey: DefaultFirebaseOptions.web.apiKey,
        httpClient: TimeoutHttpClient(timeout: const Duration(seconds: 8)),
      ),
    );

    final restFirestore = fc.Firestore(
      projectId: DefaultFirebaseOptions.web.projectId,
      idTokenProvider: desktopAuth.idToken,

      httpClient: TimeoutHttpClient(),
      cache: await firestore_cache_factory.createDesktopFirestoreCache(
        () => desktopAuth.currentUser?.uid,
      ),
    );

    desktopAuth.onSessionEnded =
        firestore_cache_factory.clearDesktopFirestoreCacheFor;
    authService = desktopAuth;
    roleService = DesktopUserRoleService(firestore: restFirestore);

    desktopScoutingStorage = SharedPreferencesScoutingStorage();
    desktopPitScoutingStorage = SharedPreferencesPitScoutingStorage();
    desktopTrexTraitReportStorage = SharedPreferencesTrexTraitReportStorage();
    desktopPrescoutingStorage = SharedPreferencesPrescoutingStorage();
    desktopPickListStorage = SharedPreferencesPickListStorage();
    desktopPostMatchReportStorage = SharedPreferencesPostMatchReportStorage();
    scoutingSyncService = DesktopScoutingSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
      storage: desktopScoutingStorage,
    );
    alertService = DesktopAccuracyAlertService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    scoutConfigSyncService = DesktopScoutConfigSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    pitScoutConfigSyncService = DesktopScoutConfigSyncService.pit(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    prescoutConfigSyncService = DesktopScoutConfigSyncService.prescout(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    pickListSyncService = DesktopPickListSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
      storage: desktopPickListStorage,
    );
    strategyBoardSyncService = DesktopStrategyBoardSyncService(
      authService: desktopAuth,
      firestore: restFirestore,

      directory: matchDirectory,
    );
    pitScoutingSyncService = DesktopPitScoutingSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
      storage: desktopPitScoutingStorage,
    );
    prescoutingSyncService = DesktopPrescoutingSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
      storage: desktopPrescoutingStorage,
    );
    assignmentSyncService = DesktopScoutAssignmentSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    traitTableSyncService = DesktopTraitTableSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    trexAssignmentsSyncService = DesktopTRexAssignmentsSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    trexTeamListSyncService = DesktopTRexTeamListSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    trexTraitReportSyncService = DesktopTrexTraitReportSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
      storage: desktopTrexTraitReportStorage,
    );
    postMatchReportSyncService = DesktopPostMatchReportSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
      storage: desktopPostMatchReportStorage,
    );
    shiftSyncService = DesktopScoutShiftSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    shiftTradeSyncService = DesktopShiftTradeSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );

    issueReportService = IssueReportService(
      write: (path, data) => restFirestore.setDocument(path, data),
    );

    telemetryService = TelemetryService(
      write: (path, data) => restFirestore.setDocument(path, data),
    );

    photoWorkerFetcher = () async {
      final doc = await restFirestore.getDocument(PhotoWorkerConfig.docPath);
      final value = doc?.fields[PhotoWorkerConfig.fieldName];
      return value is String ? value : null;
    };

    teamTbaConfig = FirestoreTbaConfig(
      remoteFetcher: () async {
        final doc = await restFirestore.getDocument('appConfig/apiKeys');
        final value = doc?.fields['tba'];
        return value is String ? value : null;
      },
    );
    assistantConfig = FirestoreAssistantConfig(
      remoteFetcher: () async {
        final doc = await restFirestore.getDocument('appConfig/apiKeys');
        final value = doc?.fields['openrouter'];
        return value is String ? value : null;
      },
    );
    activeEventSyncService = DesktopActiveEventSyncService(
      authService: desktopAuth,
      firestore: restFirestore,
    );
    remoteAssistantCache = DesktopRemoteAssistantCache(
      authService: desktopAuth,
      firestore: restFirestore,
    );
  } else {
    authService = LocalOnlyAuthService();
    roleService = LocalUserRoleService();
    assignmentSyncService = LocalOnlyScoutAssignmentSyncService();
    shiftSyncService = LocalOnlyScoutShiftSyncService();
    shiftTradeSyncService = LocalOnlyShiftTradeSyncService();
  }

  final strategyController = StrategyController(
    directory: matchDirectory,
    latestFieldIdLoader: () async => (await FieldMapCatalog().load()).latestId,
    syncService: strategyBoardSyncService,
  );
  final scoutingController = ScoutingController(
    storage: desktopScoutingStorage,
    syncService: scoutingSyncService,
    alertService: alertService,
  );
  final configController = ScoutConfigController(
    syncService: scoutConfigSyncService,
  );
  final themeController = ThemeController();
  final userRoleController = UserRoleController(
    authService: authService,
    roleService: roleService,
  );

  final tbaClient = TbaClient(
    config: teamTbaConfig ?? const CompileTimeTbaConfig(),
    httpClient: TimeoutHttpClient(),
  );
  final statboticsClient = StatboticsClient(httpClient: TimeoutHttpClient());

  final eventController = EventController(
    client: statboticsClient,
    tbaClient: tbaClient,
    syncService: activeEventSyncService,
  );

  final teamHistoryService = TeamHistoryService(
    client: statboticsClient,
    tbaClient: tbaClient,
  );
  final teamAvatarService = TeamAvatarService(client: tbaClient);

  final eventStatsController = EventStatsController(tbaClient: tbaClient);
  final eventSectionsController = EventSectionsController(tbaClient: tbaClient);
  final pickListController = PickListController(
    syncService: pickListSyncService,
  );
  final assignmentController = ScoutAssignmentController(
    syncService: assignmentSyncService,
  );

  final assistantService = assistantConfig == null
      ? null
      : AssistantService(
          backends: [
            OpenRouterAssistantBackend(
              config: assistantConfig,
              client: TimeoutHttpClient(timeout: const Duration(seconds: 90)),
            ),
            if (_isDesktop) LocalAssistantBackend(),
          ],
          cache: AssistantCache(remote: remoteAssistantCache),
        );

  final trait = traitTableSyncService;
  final traitTableController = trait == null
      ? null
      : TraitTableController(syncService: trait, assistant: assistantService);
  final shiftController = ScoutShiftController(syncService: shiftSyncService);
  final shiftTradeController = ShiftTradeController(
    syncService: shiftTradeSyncService,
  );

  final trex = trexAssignmentsSyncService;
  final trexAssignmentsController = trex == null
      ? null
      : TRexAssignmentsController(syncService: trex);

  final trexTeam = trexTeamListSyncService;
  final trexTeamListController = trexTeam == null
      ? null
      : TRexTeamListController(syncService: trexTeam);

  final trexTraitReports = trexTraitReportSyncService;
  final trexTraitReportController = trexTraitReports == null
      ? null
      : TrexTraitReportController(syncService: trexTraitReports);
  final pitScoutConfigController = PitScoutConfigController(
    syncService: pitScoutConfigSyncService,
  );
  final prescoutConfigController = PrescoutConfigController(
    syncService: prescoutConfigSyncService,
  );

  final photoWorkerConfig = PhotoWorkerConfig(
    remoteFetcher: photoWorkerFetcher,
  );
  final pitScoutingController = PitScoutingController(
    syncService: pitScoutingSyncService,
    photoStore: pit_photo_store_factory.createPitPhotoStore(),
    photoUploader: PitPhotoUploadService(
      baseUrlLoader: photoWorkerConfig.resolve,
      idTokenProvider: authService.idToken,
    ),
  );

  final prescoutingController = PrescoutingController(
    syncService: prescoutingSyncService,
  );
  final cycleLogController = CycleLogController();
  final playoffBoardController = PlayoffBoardController(
    storage: SharedPreferencesPlayoffBoardStorage(),
  );
  final postMatchReportController = PostMatchReportController(
    syncService: postMatchReportSyncService,
  );

  final telemetry = telemetryService;
  if (telemetry != null) {
    unawaited(telemetry.logEvent('app_open'));
  }

  runApp(
    StrategyApp(
      strategyController: strategyController,
      scoutingController: scoutingController,
      configController: configController,
      authService: authService,
      themeController: themeController,
      userRoleController: userRoleController,
      eventController: eventController,
      teamAvatarService: teamAvatarService,
      issueReportService: issueReportService,
      tourService: SharedPreferencesTourService(),
      telemetryService: telemetryService,
      pickListController: pickListController,
      eventStatsController: eventStatsController,
      eventSectionsController: eventSectionsController,
      assignmentController: assignmentController,
      shiftController: shiftController,
      shiftTradeController: shiftTradeController,
      pitScoutConfigController: pitScoutConfigController,
      pitScoutingController: pitScoutingController,
      prescoutConfigController: prescoutConfigController,
      prescoutingController: prescoutingController,
      cycleLogController: cycleLogController,
      playoffBoardController: playoffBoardController,
      traitTableController: traitTableController,
      trexAssignmentsController: trexAssignmentsController,
      trexTeamListController: trexTeamListController,
      trexTraitReportController: trexTraitReportController,
      postMatchReportController: postMatchReportController,
      assistant: assistantService,
      teamHistory: teamHistoryService,
      matchDirectory: matchDirectory,
    ),
  );
}
