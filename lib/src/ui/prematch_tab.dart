import 'package:flutter/material.dart';

import '../scouting/models/team_analysis.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../services/assistant/assistant_service.dart';
import '../services/match_directory.dart';
import '../state/cycle_log_controller.dart';
import '../state/event_controller.dart';
import '../state/event_sections_controller.dart';
import '../state/event_stats_controller.dart';
import '../state/pick_list_controller.dart';
import '../state/playoff_board_controller.dart';
import '../state/post_match_report_controller.dart';
import '../state/trait_table_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/event_sections_view.dart';
import '../widgets/event_stat_table_view.dart';
import '../widgets/match_schedule_row.dart';
import 'analysis_view.dart';
import 'event_picker_dialog.dart';
import 'film_review_screen.dart';
import 'match_info_view.dart';
import 'match_prediction_view.dart';
import 'pick_lists_screen.dart';
import 'playoff_ranking_screen.dart';
import 'playoff_section_screen.dart';
import 'post_match_reports_table_screen.dart';
import 'team_compare_view.dart';
import 'team_lookup_view.dart';
import 'team_summary_view.dart';
import 'trait_table_screen.dart';

enum _PrematchView {
  statbotics('Statbotics', Icons.insights_outlined),
  tba('TBA', Icons.calendar_month_outlined),
  summary('Summary', Icons.grid_on_outlined),
  teamLookup('Team lookup', Icons.person_search_outlined),
  matchInfo('Match info', Icons.event_note_outlined),
  compare('Compare', Icons.compare_arrows_rounded),
  matchPrediction('Prediction', Icons.calculate_outlined),
  traits('Traits', Icons.table_chart_outlined),
  ranking('Ranking', Icons.leaderboard_rounded),
  playoff('Playoff', Icons.emoji_events_outlined),
  film('Film', Icons.movie_creation_outlined),
  postMatch('Post match', Icons.summarize_outlined),
  pickLists('Pick lists', Icons.format_list_numbered_rounded);

  const _PrematchView(this.label, this.icon);

  final String label;
  final IconData icon;
}

class PrematchTab extends StatefulWidget {
  const PrematchTab({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    required this.playoffBoardController,
    this.cycleLogController,
    this.pickListController,
    this.eventStatsController,
    this.eventSectionsController,
    this.traitTableController,
    this.canEditTraitTable = false,
    this.assistant,
    this.postMatchReportController,
    this.userRoleController,
    this.matchDirectory,
    this.pitScoutingController,
    this.pitScoutConfigController,
    super.key,
  });

  final AssistantService? assistant;

  final EventController eventController;
  final ScoutingController scoutingController;
  final PlayoffBoardController playoffBoardController;
  final CycleLogController? cycleLogController;

  final ScoutConfigController configController;
  final PickListController? pickListController;

  final EventStatsController? eventStatsController;

  final EventSectionsController? eventSectionsController;

  final TraitTableController? traitTableController;

  final bool canEditTraitTable;

  final PostMatchReportController? postMatchReportController;

  final UserRoleController? userRoleController;

  final MatchDirectory? matchDirectory;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  @override
  State<PrematchTab> createState() => _PrematchTabState();
}

class _PrematchTabState extends State<PrematchTab> {
  _PrematchView _view = _PrematchView.tba;

  String? _statsLoadedFor;

  @override
  void initState() {
    super.initState();
    widget.eventController.addListener(_syncStats);
    _syncStats();
  }

  @override
  void didUpdateWidget(PrematchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventController != widget.eventController) {
      oldWidget.eventController.removeListener(_syncStats);
      widget.eventController.addListener(_syncStats);
      _statsLoadedFor = null;
    }

    if (oldWidget.eventStatsController != widget.eventStatsController ||
        oldWidget.eventSectionsController != widget.eventSectionsController) {
      _statsLoadedFor = null;
    }
    _syncStats();
  }

  @override
  void dispose() {
    widget.eventController.removeListener(_syncStats);
    super.dispose();
  }

  void _syncStats() {
    final stats = widget.eventStatsController;
    final sections = widget.eventSectionsController;
    if (stats == null && sections == null) return;
    final key = widget.eventController.eventKey;
    if (key == _statsLoadedFor) return;
    _statsLoadedFor = key;
    stats?.load(key);
    sections?.load(key);
  }

  void _reloadSections() {
    widget.eventSectionsController?.load(widget.eventController.eventKey);
  }

  Widget _eventContent(_PrematchView lens) {
    final eventController = widget.eventController;
    return AnimatedBuilder(
      animation: Listenable.merge([
        eventController,
        widget.scoutingController,
        widget.configController,

        widget.eventStatsController,

        widget.eventSectionsController,
      ]),
      builder: (context, _) {
        if (!eventController.hasEvent) {
          return _EmptyState(
            icon: Icons.flag_outlined,
            message:
                'No event selected.\n'
                'Select an event to load team rosters, stats, and schedule.',
            onSelectEvent: () => showEventPicker(context, eventController),
          );
        }

        if (lens == _PrematchView.tba) {
          return _buildTbaSchedule(eventController);
        }

        if (eventController.isLoading && eventController.displayTeams.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (eventController.error != null) {
          return _EmptyState(
            icon: Icons.error_outline_rounded,
            message:
                'Could not load event data.\n${eventController.error}\n\n'
                'Check the event in Settings and try again.',
            onRetry: eventController.refresh,
          );
        }

        final notice = eventController.dataNotice;

        final teams = eventController.displayTeams;
        if (teams.isEmpty) {
          return _EmptyState(
            icon: Icons.group_outlined,
            message:
                notice ??
                'No team data found for "${eventController.eventKey}".',
            onRetry: notice == null ? eventController.refresh : null,
          );
        }

        final stats = widget.eventStatsController;
        final sorted = teams.toList(growable: false)
          ..sort((a, b) {
            if (eventController.teamsAreRosterOnly) {
              final ra = stats?.rankFor(a.team);
              final rb = stats?.rankFor(b.team);
              if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
              if (ra != null && rb == null) return -1;
              if (ra == null && rb != null) return 1;
              return a.team.compareTo(b.team);
            }
            final ea = a.epa.totalPoints;
            final eb = b.epa.totalPoints;
            if (ea == null && eb == null) return 0;
            if (ea == null) return 1;
            if (eb == null) return -1;
            return eb.compareTo(ea);
          });

        final analysisByTeam = ScoutingAnalysis.aggregateByTeam(
          widget.scoutingController.entries,
          config: widget.configController.config,
        );

        final view = _EventView(
          statsController: widget.eventStatsController,
          eventName: eventController.eventName,
          eventKey: eventController.eventKey,
          teams: sorted,
          nicknames: eventController.teamNicknames,
          analysisByTeam: analysisByTeam,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          cycleLogController: widget.cycleLogController,
          assistant: widget.assistant,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,

          onRefresh: () async {
            await Future.wait<void>([
              eventController.refresh(),
              if (stats != null) stats.load(eventController.eventKey),
            ]);
          },
        );

        final banner = [
          eventController.error,
          notice,
        ].whereType<String>().join('\n\n');
        if (banner.isEmpty) {
          return view;
        }

        return Column(
          children: [
            _DataSourceNotice(text: banner),
            Expanded(child: view),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DestinationBar(
          selected: _view,
          available: _availableViews,
          onSelected: (view) => setState(() => _view = view),
        ),
        Expanded(
          child: IndexedStack(
            index: _availableViews.indexOf(_view),
            sizing: StackFit.expand,
            children: [
              for (final view in _availableViews) _destinationBody(view),
            ],
          ),
        ),
      ],
    );
  }

  List<_PrematchView> get _availableViews => <_PrematchView>[
    for (final view in _PrematchView.values)
      if ((view != _PrematchView.pickLists ||
              widget.pickListController != null) &&
          (view != _PrematchView.traits ||
              widget.traitTableController != null) &&
          (view != _PrematchView.postMatch ||
              widget.postMatchReportController != null))
        view,
  ];

  Widget _destinationBody(_PrematchView view) {
    switch (view) {
      case _PrematchView.statbotics:
      case _PrematchView.tba:
        return _eventContent(view);
      case _PrematchView.summary:
        return TeamSummaryView(
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          eventController: widget.eventController,
        );
      case _PrematchView.teamLookup:
        return TeamLookupView(
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          eventController: widget.eventController,
          assistant: widget.assistant,
        );
      case _PrematchView.matchInfo:
        return MatchInfoView(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,
          assistant: widget.assistant,
        );
      case _PrematchView.compare:
        return TeamCompareView(
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          eventController: widget.eventController,
          assistant: widget.assistant,
        );
      case _PrematchView.matchPrediction:
        return MatchPredictionView(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
        );
      case _PrematchView.traits:
        return TraitTableScreen(
          controller: widget.traitTableController!,
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          canEdit: widget.canEditTraitTable,
        );
      case _PrematchView.ranking:
        return PlayoffRankingScreen(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          pickListController: widget.pickListController,
          assistant: widget.assistant,
          embedded: true,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,
        );
      case _PrematchView.playoff:
        return PlayoffSectionScreen(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          boardController: widget.playoffBoardController,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,
        );
      case _PrematchView.film:
        return FilmReviewScreen(
          scoutingController: widget.scoutingController,
          cycleLogController: widget.cycleLogController,
          embedded: true,
          tbaClient: widget.eventController.tbaClient,
          matchDirectory: widget.matchDirectory,
          eventKey: widget.eventController.eventKey,
          postMatchReportController: widget.postMatchReportController,
          userRoleController: widget.userRoleController,
          myTeamNumber: widget.eventController.myTeamNumber,
          assistant: widget.assistant,
        );
      case _PrematchView.postMatch:
        return PostMatchReportsTableScreen(
          controller: widget.postMatchReportController!,
          eventKey: widget.eventController.eventKey,
          userRoleController: widget.userRoleController,
          cycleLogController: widget.cycleLogController,
          tbaClient: widget.eventController.tbaClient,
          myTeamNumber: widget.eventController.myTeamNumber,
          assistant: widget.assistant,
        );
      case _PrematchView.pickLists:
        return PickListsScreen(
          controller: widget.pickListController!,
          embedded: true,
        );
    }
  }

  Widget _buildTbaSchedule(EventController eventController) {
    final matches = sortMatchesByCompLevel(eventController.matches);
    if (matches.isEmpty) {
      if (eventController.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EmptyState(
        icon: Icons.calendar_month_outlined,
        message:
            eventController.scheduleError ??
            eventController.dataNotice ??
            'No schedule for "${eventController.eventKey}" yet.',
        onRetry: eventController.refresh,
      );
    }

    final stats = widget.eventStatsController;
    final sections = widget.eventSectionsController;

    final schedule = RefreshIndicator(
      onRefresh: () async {
        await Future.wait<void>([
          eventController.refresh(),
          if (stats != null) stats.load(eventController.eventKey),
          if (sections != null) sections.load(eventController.eventKey),
        ]);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            slivers: <Widget>[
              if (stats != null)
                SliverToBoxAdapter(
                  child: EventStatTableView(controller: stats),
                ),

              if (sections != null)
                SliverToBoxAdapter(
                  child: EventSectionsView(
                    controller: sections,
                    onSelectionChanged: _reloadSections,
                  ),
                ),
              SliverList.separated(
                itemCount: matches.length,
                separatorBuilder: (context, _) => Divider(
                  height: 1,
                  color: StrategyPalette.borderOf(context),
                ),
                itemBuilder: (context, index) => MatchScheduleRow(
                  match: matches[index],
                  nicknames: eventController.teamNicknames,

                  tbaMatch: sections?.matchFor(matches[index].key),
                  showResult:
                      sections?.isVisible(EventSection.matchResults) ?? false,
                  showVideo:
                      sections?.isVisible(EventSection.matchVideos) ?? false,
                  showRankingPoints:
                      sections?.isVisible(EventSection.rankingPoints) ?? false,
                  prediction: sections?.predictionFor(matches[index].key),
                  showPrediction:
                      sections?.isVisible(EventSection.predictedScores) ??
                      false,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        ),
      ),
    );

    final banner = [
      eventController.scheduleError,
      eventController.dataNotice,
    ].whereType<String>().join('\n\n');
    if (banner.isEmpty) {
      return schedule;
    }
    return Column(
      children: [
        _DataSourceNotice(text: banner),
        Expanded(child: schedule),
      ],
    );
  }
}

class _DestinationBar extends StatefulWidget {
  const _DestinationBar({
    required this.selected,
    required this.available,
    required this.onSelected,
  });

  final _PrematchView selected;
  final List<_PrematchView> available;
  final ValueChanged<_PrematchView> onSelected;

  @override
  State<_DestinationBar> createState() => _DestinationBarState();
}

class _DestinationBarState extends State<_DestinationBar> {
  final ScrollController _scrollController = ScrollController();

  bool _showLeadingFade = false;
  bool _showTrailingFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFades);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFades() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final showLeading = position.pixels > position.minScrollExtent + 1;
    final showTrailing = position.pixels < position.maxScrollExtent - 1;
    if (showLeading != _showLeadingFade || showTrailing != _showTrailingFade) {
      setState(() {
        _showLeadingFade = showLeading;
        _showTrailingFade = showTrailing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Prematch views',
      child: SizedBox(
        height: 56,
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0.0, 0.1, 0.9, 1.0],
            colors: [
              Colors.white.withValues(alpha: _showLeadingFade ? 0 : 1),
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: _showTrailingFade ? 0 : 1),
            ],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _updateFades();
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: widget.available.length,
              separatorBuilder: (context, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final view = widget.available[index];
                return _DestinationChip(
                  view: view,
                  isSelected: view == widget.selected,
                  onTap: () => widget.onSelected(view),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.view,
    required this.isSelected,
    required this.onTap,
  });

  final _PrematchView view;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = isSelected
        ? StrategyPalette.chipSelectedOf(context)
        : StrategyPalette.chipUnselectedOf(context);
    final foreground = isSelected
        ? StrategyPalette.onChipSelectedOf(context)
        : StrategyPalette.onChipUnselectedOf(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: view.label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(view.icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  view.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventView extends StatelessWidget {
  const _EventView({
    required this.eventName,
    required this.eventKey,
    required this.teams,
    required this.nicknames,
    required this.analysisByTeam,
    required this.scoutingController,
    required this.configController,
    required this.onRefresh,
    this.statsController,
    this.cycleLogController,
    this.assistant,
    this.pitScoutingController,
    this.pitScoutConfigController,
  });

  final EventStatsController? statsController;

  final String eventName;
  final String eventKey;
  final List<StatboticsTeamEvent> teams;
  final Map<int, String> nicknames;
  final Map<int, TeamAnalysis> analysisByTeam;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final CycleLogController? cycleLogController;
  final AssistantService? assistant;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: teams.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '$eventKey — ${teams.length} teams',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ranked by EPA, joined with your scouting. Tap a '
                        'scouted team for its breakdown. Pull to refresh.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final teamEvent = teams[index - 1];
              return _TeamCard(
                teamEvent: teamEvent,
                epaRank: index,
                tbaRank: statsController?.rankFor(teamEvent.team),
                opr: statsController?.oprFor(teamEvent.team),
                tbaPercentile: statsController?.rankPercentileFor(
                  teamEvent.team,
                ),
                nickname: nicknames[teamEvent.team],
                analysis: analysisByTeam[teamEvent.team],
                scoutingController: scoutingController,
                configController: configController,
                cycleLogController: cycleLogController,
                assistant: assistant,
                eventKey: eventKey,
                pitScoutingController: pitScoutingController,
                pitScoutConfigController: pitScoutConfigController,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.teamEvent,
    required this.epaRank,
    this.tbaRank,
    this.opr,
    this.tbaPercentile,
    required this.scoutingController,
    required this.configController,
    this.nickname,
    this.analysis,
    this.cycleLogController,
    this.assistant,
    this.eventKey = '',
    this.pitScoutingController,
    this.pitScoutConfigController,
  });

  final StatboticsTeamEvent teamEvent;
  final int epaRank;

  final AssistantService? assistant;
  final String eventKey;

  final int? tbaRank;

  final num? opr;

  final double? tbaPercentile;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final String? nickname;
  final TeamAnalysis? analysis;
  final CycleLogController? cycleLogController;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  String? get _tbaLine {
    final parts = <String>[];
    if (tbaRank != null) parts.add('TBA #$tbaRank');
    if (opr != null) parts.add('OPR ${opr!.toStringAsFixed(1)}');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final te = teamEvent;
    final epa = te.epa.totalPoints;
    final a = analysis;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: a == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TeamAnalysisScreen(
                    controller: scoutingController,
                    configController: configController,
                    cycleLogController: cycleLogController,
                    teamNumber: te.team,
                    assistant: assistant,
                    eventKey: eventKey,
                    pitScoutingController: pitScoutingController,
                    pitScoutConfigController: pitScoutConfigController,
                  ),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '#$epaRank',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      te.team.toString(),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (nickname != null && nickname!.isNotEmpty)
                      Text(
                        nickname!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (a != null)
                      Text(
                        'Scouted ${a.matchCount} '
                        '${a.matchCount == 1 ? 'match' : 'matches'} · '
                        'IQM ${a.iqmTotalScore.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'Not scouted yet',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (_tbaLine != null)
                      Text(
                        _tbaLine!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StrategyPalette.metricToneOf(
                            context,
                            tbaPercentile,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  te.record,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      epa != null ? epa.toStringAsFixed(1) : '--',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.end,
                    ),
                    Text(
                      'EPA',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataSourceNotice extends StatelessWidget {
  const _DataSourceNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.onRetry,
    this.onSelectEvent,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSelectEvent;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      message: message,
      actions: [
        if (onSelectEvent != null)
          FilledButton.icon(
            onPressed: onSelectEvent,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Select event'),
          ),
        if (onRetry != null)
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
      ],
    );
  }
}
