import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../scouting/models/team_analysis.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/services/team_filters.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/prescouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../services/assistant/assistant_service.dart';
import '../services/statbotics/team_history_service.dart';
import '../services/team_avatar_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/event_controller.dart';
import '../state/event_stats_controller.dart';
import '../state/playoff_board_controller.dart';
import '../state/post_match_report_controller.dart';
import '../state/trex_trait_report_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/event_stat_table_view.dart';
import '../widgets/glass_popup_menu.dart';
import '../widgets/match_schedule_row.dart';
import '../widgets/segment_label.dart';
import 'event_picker_dialog.dart';
import 'match_hub/match_hub_launcher.dart';
import 'match_info_view.dart';
import 'match_prediction_view.dart';
import 'playoff_ranking_screen.dart';
import 'playoff_section_screen.dart';
import 'team_compare_view.dart';
import 'team_filter_bar.dart';
import 'team_hub_screen.dart';
import 'team_lookup_view.dart';
import 'team_summary_view.dart';
import 'glass_chrome.dart';

enum _PrematchView {
  statbotics('Statbotics', Icons.insights_outlined),
  tba('TBA', Icons.calendar_month_outlined),
  summary('Summary', Icons.grid_on_outlined),
  teamLookup('Team lookup', Icons.person_search_outlined),
  matchInfo('Match info', Icons.event_note_outlined),
  compare('Compare', Icons.compare_arrows_rounded),
  matchPrediction('Prediction', Icons.calculate_outlined),
  ranking('Ranking', Icons.leaderboard_rounded),
  playoff('Playoff', Icons.emoji_events_outlined);

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
    this.eventStatsController,
    this.assistant,
    this.userRoleController,
    this.pitScoutingController,
    this.pitScoutConfigController,
    this.prescoutingController,
    this.postMatchReportController,
    this.teamHistory,
    this.trexTraitReportController,
    this.teamAvatarService,
    super.key,
  });

  final AssistantService? assistant;

  final EventController eventController;
  final ScoutingController scoutingController;
  final PlayoffBoardController playoffBoardController;
  final CycleLogController? cycleLogController;

  final ScoutConfigController configController;

  final EventStatsController? eventStatsController;

  final UserRoleController? userRoleController;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  final PrescoutingController? prescoutingController;

  final PostMatchReportController? postMatchReportController;

  final TeamHistoryService? teamHistory;

  final TrexTraitReportController? trexTraitReportController;

  final TeamAvatarService? teamAvatarService;

  @override
  State<PrematchTab> createState() => _PrematchTabState();
}

enum _TeamSort {
  rating('Rating'),
  tbaRank('TBA rank'),
  opr('OPR'),
  scouted('Scouted'),
  number('Number');

  const _TeamSort(this.label);

  final String label;
}

int _missingLast<T extends Comparable<Object>>(
  T? a,
  T? b, {
  bool descending = false,
}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return descending ? b.compareTo(a) : a.compareTo(b);
}

class _PrematchTabState extends State<PrematchTab> {
  _PrematchView _view = _PrematchView.tba;

  bool get _canPublishSummaries =>
      widget.userRoleController?.roles.canPublishSummaries ?? false;

  void _openTeam(int team) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeamHubScreen(
          teamNumber: team,
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          statsController: widget.eventStatsController,
          cycleLogController: widget.cycleLogController,
          assistant: widget.assistant,
          teamHistory: widget.teamHistory,
          canPublishSummaries: _canPublishSummaries,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,
          prescoutingController: widget.prescoutingController,
          trexTraitReportController: widget.trexTraitReportController,
          postMatchReportController: widget.postMatchReportController,
          userRoleController: widget.userRoleController,
          teamAvatarService: widget.teamAvatarService,
        ),
      ),
    );
  }

  String? _statsLoadedFor;

  _TeamSort _teamSort = _TeamSort.rating;

  final Set<TeamFilter> _filters = <TeamFilter>{};
  bool _filtersOpen = false;

  String? _filtersEventKey;

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

    if (oldWidget.eventStatsController != widget.eventStatsController) {
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
    if (stats == null) return;
    final key = widget.eventController.eventKey;
    if (key == _statsLoadedFor) return;
    _statsLoadedFor = key;
    stats.load(key);
  }

  Widget _eventContent(_PrematchView lens) {
    final eventController = widget.eventController;
    return AnimatedBuilder(
      animation: Listenable.merge([
        eventController,
        widget.scoutingController,
        widget.configController,

        widget.eventStatsController,
        widget.pitScoutingController,
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
        final ratingOrder = teams.toList(growable: false)
          ..sort((a, b) {
            if (eventController.teamsAreRosterOnly) {
              final byRank = _missingLast(
                stats?.rankFor(a.team),
                stats?.rankFor(b.team),
              );
              return byRank != 0 ? byRank : a.team.compareTo(b.team);
            }
            final byEpa = _missingLast(
              a.epa.totalPoints,
              b.epa.totalPoints,
              descending: true,
            );
            return byEpa != 0 ? byEpa : a.team.compareTo(b.team);
          });

        final ratingRank = <int, int>{
          for (var i = 0; i < ratingOrder.length; i++)
            ratingOrder[i].team: i + 1,
        };

        final analysisByTeam = ScoutingAnalysis.aggregateByTeam(
          widget.scoutingController.entries,
          config: widget.configController.config,
        );

        int byKey(StatboticsTeamEvent a, StatboticsTeamEvent b) =>
            switch (_teamSort) {
              _TeamSort.rating => 0,
              _TeamSort.tbaRank => _missingLast(
                stats?.rankFor(a.team),
                stats?.rankFor(b.team),
              ),
              _TeamSort.opr => _missingLast(
                stats?.oprFor(a.team),
                stats?.oprFor(b.team),
                descending: true,
              ),
              _TeamSort.scouted => _missingLast(
                analysisByTeam[a.team]?.iqmTotalScore,
                analysisByTeam[b.team]?.iqmTotalScore,
                descending: true,
              ),
              _TeamSort.number => a.team.compareTo(b.team),
            };
        final sorted = _teamSort == _TeamSort.rating
            ? ratingOrder
            : (ratingOrder.toList(growable: false)..sort((a, b) {
                final primary = byKey(a, b);

                return primary != 0
                    ? primary
                    : ratingRank[a.team]!.compareTo(ratingRank[b.team]!);
              }));

        if (eventController.eventKey != _filtersEventKey) {
          _filtersEventKey = eventController.eventKey;
          _filters.clear();
          _filtersOpen = false;
        }
        final showPitFilters = widget.pitScoutingController != null;
        final active = {
          for (final filter in _filters)
            if (showPitFilters || !filter.needsPit) filter,
        };
        final filterResults = TeamFilters.evaluate(
          teams: [for (final t in teams) t.team],
          entries: widget.scoutingController.entries,
          pitByTeam: mostRecentPitEntryByTeam(
            widget.pitScoutingController?.entries,
          ),
          eventKey: eventController.eventKey,
          config: widget.configController.config,
        );
        final visible = active.isEmpty
            ? sorted
            : [
                for (final t in sorted)
                  if (filterResults.passes(t.team, active)) t,
              ];

        final ratingName = eventController.teamsAreRosterOnly
            ? 'TBA rank'
            : eventController.ratingsSource == RatingsSource.match13
            ? 'xP'
            : 'EPA';

        final view = _EventView(
          statsController: widget.eventStatsController,
          eventName: eventController.eventName,
          eventKey: eventController.eventKey,
          teams: visible,
          totalTeams: teams.length,
          filterResults: filterResults,
          activeFilters: active,
          showPitFilters: showPitFilters,
          onToggleFilter: (filter, on) => setState(() {
            on ? _filters.add(filter) : _filters.remove(filter);
          }),
          onClearFilters: () => setState(_filters.clear),
          filtersOpen: _filtersOpen,
          onFiltersOpenChanged: (open) => setState(() => _filtersOpen = open),
          ratingRank: ratingRank,
          sort: _teamSort,
          sortLine: switch (_teamSort) {
            _TeamSort.rating => 'Ranked by $ratingName',
            _TeamSort.tbaRank => 'Ranked by TBA rank',
            _TeamSort.opr => 'Ranked by OPR',
            _TeamSort.scouted => 'Ranked by scouted IQM total',
            _TeamSort.number => 'Sorted by team number',
          },
          onSortChanged: (sort) => setState(() => _teamSort = sort),
          nicknames: eventController.teamNicknames,
          analysisByTeam: analysisByTeam,
          onOpenTeam: _openTeam,

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
    final available = _availableViews;

    final selected = available.contains(_view) ? _view : available.first;
    return Column(
      children: [
        _DestinationHeader(
          selected: selected,
          available: available,
          onSelected: (view) => setState(() => _view = view),
        ),
        Expanded(
          child: IndexedStack(
            index: available.indexOf(selected),
            sizing: StackFit.expand,
            children: [for (final view in available) _destinationBody(view)],
          ),
        ),
      ],
    );
  }

  List<_PrematchView> get _availableViews => _PrematchView.values;

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
          canPublishSummaries: _canPublishSummaries,
        );
      case _PrematchView.matchInfo:
        return MatchInfoView(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,
          prescoutingController: widget.prescoutingController,
          assistant: widget.assistant,
          playoffBoardController: widget.playoffBoardController,
          postMatchReportController: widget.postMatchReportController,
          userRoleController: widget.userRoleController,
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
      case _PrematchView.ranking:
        return PlayoffRankingScreen(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          onOpenTeam: _openTeam,
          embedded: true,
          statsController: widget.eventStatsController,
        );
      case _PrematchView.playoff:
        return PlayoffSectionScreen(
          eventController: widget.eventController,
          scoutingController: widget.scoutingController,
          configController: widget.configController,
          boardController: widget.playoffBoardController,
          pitScoutingController: widget.pitScoutingController,
          pitScoutConfigController: widget.pitScoutConfigController,
          eventStatsController: widget.eventStatsController,
          trexTraitReportController: widget.trexTraitReportController,
          assistant: widget.assistant,
          canPublishSummaries: _canPublishSummaries,
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

    final schedule = RefreshIndicator(
      onRefresh: () async {
        await Future.wait<void>([
          eventController.refresh(),
          if (stats != null) stats.load(eventController.eventKey),
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
              SliverList.separated(
                itemCount: matches.length,
                separatorBuilder: (context, _) => Divider(
                  height: 1,
                  color: StrategyPalette.borderOf(context),
                ),
                itemBuilder: (context, index) => MatchScheduleRow(
                  match: matches[index],
                  nicknames: eventController.teamNicknames,
                  onTap: MatchHubScope.opener(context, matches[index]),
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
    final body = banner.isEmpty
        ? schedule
        : Column(
            children: [
              _DataSourceNotice(text: banner),
              Expanded(child: schedule),
            ],
          );
    return Padding(
      padding: EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
      child: body,
    );
  }
}

class _DestinationHeader extends StatelessWidget {
  const _DestinationHeader({
    required this.selected,
    required this.available,
    required this.onSelected,
  });

  final _PrematchView selected;
  final List<_PrematchView> available;
  final ValueChanged<_PrematchView> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Prematch section: ${selected.label}',
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(selected.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GlassPopupMenuButton<_PrematchView>(
                tooltip: 'Prematch sections',
                icon: const Icon(Icons.menu),
                onSelected: onSelected,
                itemBuilder: (_) => available.map((view) {
                  final isSelected = view == selected;
                  return PopupMenuItem<_PrematchView>(
                    value: view,
                    child: Row(
                      children: [
                        Icon(
                          view.icon,
                          size: 20,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          view.label,
                          style: isSelected
                              ? TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                )
                              : null,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
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
    required this.totalTeams,
    required this.filterResults,
    required this.activeFilters,
    required this.showPitFilters,
    required this.onToggleFilter,
    required this.onClearFilters,
    required this.filtersOpen,
    required this.onFiltersOpenChanged,
    required this.ratingRank,
    required this.sort,
    required this.sortLine,
    required this.onSortChanged,
    required this.nicknames,
    required this.analysisByTeam,
    required this.onOpenTeam,
    required this.onRefresh,
    this.statsController,
  });

  final EventStatsController? statsController;

  final String eventName;
  final String eventKey;

  final List<StatboticsTeamEvent> teams;

  final int totalTeams;
  final TeamFilterResults filterResults;
  final Set<TeamFilter> activeFilters;
  final bool showPitFilters;
  final void Function(TeamFilter filter, bool selected) onToggleFilter;
  final VoidCallback onClearFilters;
  final bool filtersOpen;
  final ValueChanged<bool> onFiltersOpenChanged;

  final Map<int, int> ratingRank;
  final _TeamSort sort;

  final String sortLine;
  final ValueChanged<_TeamSort> onSortChanged;
  final Map<int, String> nicknames;
  final Map<int, TeamAnalysis> analysisByTeam;
  final ValueChanged<int> onOpenTeam;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
      child: RefreshIndicator(
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
                          '$eventKey · $totalTeams teams',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<_TeamSort>(
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: <ButtonSegment<_TeamSort>>[
                              for (final option in _TeamSort.values)
                                ButtonSegment<_TeamSort>(
                                  value: option,
                                  label: SegmentLabel(option.label),
                                ),
                            ],
                            selected: <_TeamSort>{sort},
                            onSelectionChanged: (s) => onSortChanged(s.first),
                            showSelectedIcon: false,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$sortLine, joined with your scouting. Tap a '
                          'team to open its page. Pull to refresh.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        TeamFilterBar(
                          results: filterResults,
                          active: activeFilters,
                          shown: teams.length,
                          showPitFilters: showPitFilters,
                          onToggle: onToggleFilter,
                          onClear: onClearFilters,
                          open: filtersOpen,
                          onOpenChanged: onFiltersOpenChanged,
                        ),
                      ],
                    ),
                  );
                }
                final teamEvent = teams[index - 1];
                return _TeamCard(
                  teamEvent: teamEvent,
                  epaRank: ratingRank[teamEvent.team] ?? index,
                  tbaRank: statsController?.rankFor(teamEvent.team),
                  opr: statsController?.oprFor(teamEvent.team),
                  tbaPercentile: statsController?.rankPercentileFor(
                    teamEvent.team,
                  ),
                  nickname: nicknames[teamEvent.team],
                  analysis: analysisByTeam[teamEvent.team],
                  onOpenTeam: onOpenTeam,
                );
              },
            ),
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
    required this.onOpenTeam,
    this.tbaRank,
    this.opr,
    this.tbaPercentile,
    this.nickname,
    this.analysis,
  });

  final StatboticsTeamEvent teamEvent;
  final int epaRank;
  final ValueChanged<int> onOpenTeam;

  final int? tbaRank;

  final num? opr;

  final double? tbaPercentile;
  final String? nickname;
  final TeamAnalysis? analysis;

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
        onTap: () => onOpenTeam(te.team),
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
