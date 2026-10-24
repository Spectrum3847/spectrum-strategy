import 'dart:async';

import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../state/event_controller.dart';
import '../state/event_stats_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/match_schedule_row.dart';
import '../widgets/segment_label.dart';
import 'glass_chrome.dart';
import 'match_hub/match_hub_launcher.dart';
import 'team_link.dart';
import 'team_matches_view.dart';

enum _ScheduleView { team, matches, teams }

class ScheduleTab extends StatefulWidget {
  const ScheduleTab({
    required this.eventController,
    this.eventStatsController,
    super.key,
  });

  final EventController eventController;

  final EventStatsController? eventStatsController;

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  final TextEditingController _searchController = TextEditingController();
  _ScheduleView _view = _ScheduleView.matches;
  String _query = '';

  String? _statsLoadedFor;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    widget.eventController.addListener(_syncStats);
    _syncStats();
  }

  @override
  void didUpdateWidget(ScheduleTab oldWidget) {
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
    _searchController.dispose();
    super.dispose();
  }

  void _syncStats() {
    final stats = widget.eventStatsController;
    if (stats == null) return;
    final key = widget.eventController.eventKey;
    if (key == _statsLoadedFor) return;
    _statsLoadedFor = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(stats.load(key));
    });
  }

  ValueChanged<StatboticsMatch>? _matchOpener(BuildContext context) {
    final launcher = MatchHubScope.maybeOf(context);
    return launcher == null ? null : (match) => launcher.open(context, match);
  }

  void _onViewChanged(Set<_ScheduleView> selection) {
    _searchController.clear();
    setState(() => _view = selection.first);
  }

  bool _teamMatchesQuery(int team, Map<int, String> nicknames) {
    if (team.toString().contains(_query)) return true;
    final nick = nicknames[team];
    return nick != null && nick.toLowerCase().contains(_query);
  }

  List<int> _sortedTeams(EventController controller) => <int>{
    ...controller.teamNumbers,
    ...controller.teamNicknames.keys,
  }.toList()..sort();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable?>[
        widget.eventController,
        widget.eventStatsController,
      ]),
      builder: (context, _) {
        final controller = widget.eventController;

        if (!controller.hasEvent) {
          return const EmptyState(
            icon: Icons.calendar_month_outlined,
            message:
                'No event selected.\n'
                'Pick your event in Settings to load its match schedule and '
                'team list.',
          );
        }

        final matches = sortMatchesByCompLevel(controller.matches);
        final teams = _sortedTeams(controller);
        final nicknames = controller.teamNicknames;

        if (matches.isEmpty && teams.isEmpty) {
          if (controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return EmptyState(
            icon: Icons.calendar_month_outlined,
            message:
                controller.scheduleError ??
                controller.dataNotice ??
                'No schedule or team list for "${controller.eventKey}" yet.',
            actions: [
              OutlinedButton.icon(
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          );
        }

        return Column(
          children: [
            _FilterBar(
              eventName: controller.eventName.isNotEmpty
                  ? controller.eventName
                  : controller.eventKey,
              view: _view,
              onViewChanged: _onViewChanged,
              searchController: _searchController,
              hasQuery: _query.isNotEmpty,
              matchCount: matches.length,
              teamCount: teams.length,
            ),
            Expanded(
              child: switch (_view) {
                _ScheduleView.team => TeamMatchesView(
                  eventController: controller,
                  eventStatsController: widget.eventStatsController,
                  matches: matches,
                  teams: teams,
                  onOpenMatch: _matchOpener(context),
                ),
                _ScheduleView.matches => _buildMatches(
                  matches,
                  nicknames,
                  controller.refresh,
                ),
                _ScheduleView.teams => _buildTeams(
                  teams,
                  nicknames,
                  controller.refresh,
                ),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMatches(
    List<StatboticsMatch> matches,
    Map<int, String> nicknames,
    Future<void> Function() onRefresh,
  ) {
    final visible = _query.isEmpty
        ? matches
        : matches
              .where(
                (m) =>
                    m.displayName.toLowerCase().contains(_query) ||
                    m.allTeams.any((t) => _teamMatchesQuery(t, nicknames)),
              )
              .toList(growable: false);

    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        message: 'No match name or team matches that search.',
      );
    }

    return _RefreshableList(
      onRefresh: onRefresh,
      itemCount: visible.length,
      itemBuilder: (context, index) => MatchScheduleRow(
        match: visible[index],
        nicknames: nicknames,
        onTap: MatchHubScope.opener(context, visible[index]),
      ),
    );
  }

  Widget _buildTeams(
    List<int> teams,
    Map<int, String> nicknames,
    Future<void> Function() onRefresh,
  ) {
    final visible = _query.isEmpty
        ? teams
        : teams
              .where((t) => _teamMatchesQuery(t, nicknames))
              .toList(growable: false);

    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        message: 'No team number or name matches that search.',
      );
    }

    return _RefreshableList(
      onRefresh: onRefresh,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final team = visible[index];
        final nickname = nicknames[team];
        return TeamLink(
          team: team,
          child: ListTile(
            title: Text(
              team.toString(),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              (nickname == null || nickname.isEmpty)
                  ? 'Name unavailable'
                  : nickname,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.eventName,
    required this.view,
    required this.onViewChanged,
    required this.searchController,
    required this.hasQuery,
    required this.matchCount,
    required this.teamCount,
  });

  final String eventName;
  final _ScheduleView view;
  final ValueChanged<Set<_ScheduleView>> onViewChanged;
  final TextEditingController searchController;
  final bool hasQuery;
  final int matchCount;
  final int teamCount;

  @override
  Widget build(BuildContext context) {
    final isMatches = view == _ScheduleView.matches;
    return Material(
      elevation: 0,
      color: StrategyPalette.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              eventName,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_ScheduleView>(
                segments: const [
                  ButtonSegment(
                    value: _ScheduleView.team,
                    label: SegmentLabel('Team'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: _ScheduleView.matches,
                    label: SegmentLabel('Matches'),
                    icon: Icon(Icons.calendar_month_outlined),
                  ),
                  ButtonSegment(
                    value: _ScheduleView.teams,
                    label: SegmentLabel('Teams'),
                    icon: Icon(Icons.group_outlined),
                  ),
                ],
                selected: {view},
                onSelectionChanged: onViewChanged,
                showSelectedIcon: false,
              ),
            ),
            if (view != _ScheduleView.team) ...[
              const SizedBox(height: 8),
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: isMatches
                      ? 'Search $matchCount matches'
                      : 'Search $teamCount teams',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  suffixIcon: hasQuery
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          tooltip: 'Clear search',
                          onPressed: searchController.clear,
                        )
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RefreshableList extends StatelessWidget {
  const _RefreshableList({
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
  });

  final Future<void> Function() onRefresh;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.separated(
            padding:
                const EdgeInsets.symmetric(vertical: 8) +
                EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
            itemCount: itemCount,
            separatorBuilder: (context, _) =>
                Divider(height: 1, color: StrategyPalette.borderOf(context)),
            itemBuilder: itemBuilder,
          ),
        ),
      ),
    );
  }
}
