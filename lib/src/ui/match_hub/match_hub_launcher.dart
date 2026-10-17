import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../../models/match_brief.dart';
import '../../models/user_role.dart';
import '../../scouting/services/match_hub_stats.dart';
import '../../scouting/state/pit_scout_config_controller.dart';
import '../../scouting/state/pit_scouting_controller.dart';
import '../../scouting/state/prescouting_controller.dart';
import '../../scouting/state/scout_config_controller.dart';
import '../../scouting/state/scouting_controller.dart';
import '../../services/assistant/assistant_service.dart';
import '../../services/team_avatar_service.dart';
import '../../state/cycle_log_controller.dart';
import '../../state/event_controller.dart';
import '../../state/match_brief_controller.dart';
import '../../state/post_match_report_controller.dart';
import '../../state/strategy_controller.dart';
import '../../state/user_role_controller.dart';
import '../match_info_view.dart' show mostRecentPitEntryByTeam;
import 'match_hub_screen.dart';

class MatchHubLauncher {
  const MatchHubLauncher({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    required this.strategyController,
    required this.openTeam,
    this.briefController,
    this.postMatchReportController,
    this.userRoleController,
    this.cycleLogController,
    this.pitScoutingController,
    this.pitScoutConfigController,
    this.prescoutingController,
    this.teamAvatarService,
    this.assistant,
  });

  final EventController eventController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final StrategyController strategyController;

  final void Function(BuildContext context, int team) openTeam;

  final MatchBriefController? briefController;
  final PostMatchReportController? postMatchReportController;
  final UserRoleController? userRoleController;
  final CycleLogController? cycleLogController;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;
  final PrescoutingController? prescoutingController;
  final TeamAvatarService? teamAvatarService;
  final AssistantService? assistant;

  bool get canEdit => userRoleController?.roles.canEditMatchInfo ?? false;

  Listenable get changes => Listenable.merge(<Listenable?>[
    eventController,
    scoutingController,
    configController,
    briefController,
    userRoleController,
    pitScoutingController,
    pitScoutConfigController,
    prescoutingController,
  ]);

  MatchHubData dataFor(StatboticsMatch match) {
    return MatchHubData.build(
      match,
      nicknames: eventController.teamNicknames,
      teamEvents: <int, StatboticsTeamEvent>{
        for (final team in eventController.displayTeams) team.team: team,
      },
      scoutEntries: scoutingController.entries,
      myTeamNumber: eventController.myTeamNumber,
      config: configController.config,
      pitConfig: pitScoutConfigController?.config,
      pitEntryByTeam: mostRecentPitEntryByTeam(pitScoutingController?.entries),
      prescoutEntries: prescoutingController?.entries ?? const [],
    );
  }

  String matchIdOf(StatboticsMatch match) {
    final prefix = '${eventController.eventKey}_';
    return match.key.startsWith(prefix)
        ? match.key.substring(prefix.length)
        : match.key;
  }

  MatchBrief briefFor(StatboticsMatch match) {
    final eventKey = eventController.eventKey;
    final matchId = matchIdOf(match);
    return briefController?.briefFor(eventKey, matchId) ??
        MatchBrief(
          id: MatchBrief.idFor(eventKey, matchId),
          eventKey: eventKey,
          matchId: matchId,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
  }

  Future<void> open(BuildContext context, StatboticsMatch match) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MatchHubScreen(launcher: this, match: match),
      ),
    );
  }

  bool openByKey(BuildContext context, String matchKey) {
    final key = matchKey.toLowerCase();
    final match = eventController.matches
        .where((m) => m.key.toLowerCase() == key)
        .firstOrNull;
    if (match == null) return false;
    open(context, match);
    return true;
  }
}

class MatchHubScope extends InheritedWidget {
  const MatchHubScope({
    required this.launcher,
    required super.child,
    super.key,
  });

  final MatchHubLauncher launcher;

  static MatchHubLauncher? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MatchHubScope>();
    return scope?.launcher;
  }

  static VoidCallback? opener(BuildContext context, StatboticsMatch match) {
    final launcher = maybeOf(context);
    return launcher == null ? null : () => launcher.open(context, match);
  }

  static VoidCallback? teamOpener(BuildContext context, int team) {
    final launcher = maybeOf(context);
    return launcher == null ? null : () => launcher.openTeam(context, team);
  }

  @override
  bool updateShouldNotify(MatchHubScope oldWidget) =>
      launcher != oldWidget.launcher;
}
