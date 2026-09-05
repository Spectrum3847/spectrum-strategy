import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'scouting/state/pit_scout_config_controller.dart';
import 'scouting/state/pit_scouting_controller.dart';
import 'scouting/state/prescout_config_controller.dart';
import 'scouting/state/prescouting_controller.dart';
import 'scouting/state/scout_assignment_controller.dart';
import 'scouting/state/scout_config_controller.dart';
import 'scouting/state/scout_shift_controller.dart';
import 'scouting/state/shift_trade_controller.dart';
import 'scouting/state/scouting_controller.dart';
import 'services/assistant/assistant_service.dart';
import 'services/statbotics/team_history_service.dart';
import 'services/issue_report_service.dart';
import 'services/telemetry_service.dart';
import 'services/match_directory.dart';
import 'services/spectrum_auth_service.dart';
import 'services/tour_service.dart';
import 'services/team_avatar_service.dart';
import 'state/cycle_log_controller.dart';
import 'state/event_controller.dart';
import 'state/playoff_board_controller.dart';
import 'state/event_sections_controller.dart';
import 'state/event_stats_controller.dart';
import 'state/pick_list_controller.dart';
import 'state/post_match_report_controller.dart';
import 'state/strategy_controller.dart';
import 'state/trait_table_controller.dart';
import 'state/trex_assignments_controller.dart';
import 'state/trex_team_list_controller.dart';
import 'state/trex_trait_report_controller.dart';
import 'state/theme_controller.dart';
import 'state/user_role_controller.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';

class StrategyApp extends StatefulWidget {
  const StrategyApp({
    required this.strategyController,
    required this.scoutingController,
    required this.configController,
    required this.authService,
    required this.themeController,
    required this.userRoleController,
    required this.eventController,
    required this.pickListController,
    required this.eventStatsController,
    required this.eventSectionsController,
    required this.assignmentController,
    required this.shiftController,
    required this.shiftTradeController,
    required this.pitScoutConfigController,
    required this.pitScoutingController,
    required this.prescoutConfigController,
    required this.prescoutingController,
    required this.cycleLogController,
    required this.playoffBoardController,
    required this.postMatchReportController,
    this.teamAvatarService,
    this.issueReportService,
    this.tourService,
    this.telemetryService,
    this.traitTableController,
    this.trexAssignmentsController,
    this.trexTeamListController,
    this.trexTraitReportController,
    this.assistant,
    this.teamHistory,
    this.matchDirectory,
    super.key,
  });

  final StrategyController strategyController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final SpectrumAuthService authService;
  final ThemeController themeController;
  final UserRoleController userRoleController;
  final EventController eventController;
  final PickListController pickListController;

  final EventStatsController eventStatsController;
  final EventSectionsController eventSectionsController;
  final ScoutAssignmentController assignmentController;
  final ScoutShiftController shiftController;
  final ShiftTradeController shiftTradeController;
  final PitScoutConfigController pitScoutConfigController;
  final PitScoutingController pitScoutingController;

  final PrescoutConfigController prescoutConfigController;
  final PrescoutingController prescoutingController;
  final CycleLogController cycleLogController;
  final PlayoffBoardController playoffBoardController;
  final PostMatchReportController postMatchReportController;
  final TeamAvatarService? teamAvatarService;
  final IssueReportService? issueReportService;
  final TourService? tourService;
  final TelemetryService? telemetryService;

  final TraitTableController? traitTableController;

  final TRexAssignmentsController? trexAssignmentsController;

  final TRexTeamListController? trexTeamListController;

  final TrexTraitReportController? trexTraitReportController;

  final AssistantService? assistant;

  final TeamHistoryService? teamHistory;

  final MatchDirectory? matchDirectory;

  @override
  State<StrategyApp> createState() => _StrategyAppState();
}

class _StrategyAppState extends State<StrategyApp> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    widget.themeController.addListener(_onThemeChanged);
    _bootstrapFuture = _startBootstrap();
  }

  Future<void> _startBootstrap() {
    unawaited(widget.authService.initialize());
    return Future.wait(<Future<void>>[
      widget.strategyController.bootstrap(),
      widget.scoutingController.bootstrap(),
      widget.configController.bootstrap(),
      widget.themeController.bootstrap(),
      widget.userRoleController.bootstrap(),
      widget.eventController.bootstrap(),
      widget.pickListController.bootstrap(),
      widget.eventStatsController.bootstrap(),
      widget.eventSectionsController.bootstrap(),
      widget.pitScoutConfigController.bootstrap(),
      widget.pitScoutingController.bootstrap(),
      widget.prescoutConfigController.bootstrap(),
      widget.prescoutingController.bootstrap(),
      widget.cycleLogController.bootstrap(),
      widget.playoffBoardController.bootstrap(),
      widget.postMatchReportController.bootstrap(),
      if (widget.traitTableController != null)
        widget.traitTableController!.bootstrap(),
      if (widget.trexAssignmentsController != null)
        widget.trexAssignmentsController!.bootstrap(),
      if (widget.trexTeamListController != null)
        widget.trexTeamListController!.bootstrap(),
      if (widget.trexTraitReportController != null)
        widget.trexTraitReportController!.bootstrap(),
      widget.shiftTradeController.bootstrap(),
    ]);
  }

  void _retryBootstrap() {
    setState(() {
      _bootstrapFuture = _startBootstrap();
    });
  }

  void _onThemeChanged() => setState(() {});

  @override
  void dispose() {
    widget.themeController.removeListener(_onThemeChanged);
    widget.strategyController.dispose();
    widget.scoutingController.dispose();
    widget.configController.dispose();
    widget.authService.dispose();
    widget.themeController.dispose();
    widget.userRoleController.dispose();
    widget.eventController.dispose();
    widget.pickListController.dispose();
    widget.eventStatsController.dispose();
    widget.eventSectionsController.dispose();
    widget.assignmentController.dispose();
    widget.shiftController.dispose();
    widget.shiftTradeController.dispose();
    widget.pitScoutConfigController.dispose();
    widget.pitScoutingController.dispose();
    widget.prescoutConfigController.dispose();
    widget.prescoutingController.dispose();
    widget.cycleLogController.dispose();
    widget.playoffBoardController.dispose();
    widget.postMatchReportController.dispose();
    widget.traitTableController?.dispose();
    widget.trexAssignmentsController?.dispose();
    widget.trexTeamListController?.dispose();
    widget.trexTraitReportController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spectrum Strategy',
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: widget.themeController.themeMode,
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: child ?? const SizedBox.shrink(),
      ),
      home: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BootstrapErrorScreen(
              error: snapshot.error!,
              onRetry: _retryBootstrap,
            );
          }
          if (snapshot.connectionState != ConnectionState.done ||
              !widget.strategyController.isReady ||
              !widget.scoutingController.isReady) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AppShell(
            strategyController: widget.strategyController,
            scoutingController: widget.scoutingController,
            cycleLogController: widget.cycleLogController,
            playoffBoardController: widget.playoffBoardController,
            configController: widget.configController,
            authService: widget.authService,
            themeController: widget.themeController,
            userRoleController: widget.userRoleController,
            eventController: widget.eventController,
            pickListController: widget.pickListController,
            eventStatsController: widget.eventStatsController,
            eventSectionsController: widget.eventSectionsController,
            assignmentController: widget.assignmentController,
            shiftController: widget.shiftController,
            shiftTradeController: widget.shiftTradeController,
            pitScoutConfigController: widget.pitScoutConfigController,
            pitScoutingController: widget.pitScoutingController,
            prescoutConfigController: widget.prescoutConfigController,
            prescoutingController: widget.prescoutingController,
            postMatchReportController: widget.postMatchReportController,
            teamAvatarService: widget.teamAvatarService,
            issueReportService: widget.issueReportService,
            tourService: widget.tourService,
            telemetryService: widget.telemetryService,
            traitTableController: widget.traitTableController,
            trexAssignmentsController: widget.trexAssignmentsController,
            trexTeamListController: widget.trexTeamListController,
            trexTraitReportController: widget.trexTraitReportController,
            assistant: widget.assistant,
            teamHistory: widget.teamHistory,
            matchDirectory: widget.matchDirectory,
          );
        },
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Spectrum Strategy could not start',
                  style: textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
