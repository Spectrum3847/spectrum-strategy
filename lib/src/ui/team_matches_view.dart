import 'dart:async';

import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../models/match_forecast.dart';
import '../models/team_match_schedule.dart';
import '../state/event_controller.dart';
import '../state/event_stats_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/match_forecast_row.dart';
import '../widgets/match_schedule_row.dart';
import 'glass_chrome.dart';

class TeamMatchesView extends StatefulWidget {
  const TeamMatchesView({
    required this.eventController,
    required this.matches,
    required this.teams,
    this.eventStatsController,
    this.onOpenMatch,
    super.key,
  });

  final EventController eventController;

  final List<StatboticsMatch> matches;

  final List<int> teams;

  final EventStatsController? eventStatsController;

  final ValueChanged<StatboticsMatch>? onOpenMatch;

  @override
  State<TeamMatchesView> createState() => _TeamMatchesViewState();
}

class _TeamMatchesViewState extends State<TeamMatchesView> {
  int? _picked;
  String? _forecastsRequestedFor;

  @override
  void initState() {
    super.initState();
    widget.eventController.addListener(_syncForecasts);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncForecasts();
    });
  }

  @override
  void didUpdateWidget(TeamMatchesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventController != widget.eventController) {
      oldWidget.eventController.removeListener(_syncForecasts);
      widget.eventController.addListener(_syncForecasts);
      _forecastsRequestedFor = null;
    }
  }

  @override
  void dispose() {
    widget.eventController.removeListener(_syncForecasts);
    super.dispose();
  }

  void _syncForecasts() {
    final key = widget.eventController.eventKey;
    if (key == _forecastsRequestedFor) return;
    _forecastsRequestedFor = key;
    unawaited(widget.eventController.loadForecasts());
  }

  Future<void> _refresh() async {
    final controller = widget.eventController;
    final stats = widget.eventStatsController;
    await Future.wait<void>([
      controller.loadForecasts(force: true),
      controller.refresh(),
      if (stats != null) stats.load(controller.eventKey),
    ]);
  }

  int? get _team {
    final picked = _picked;
    if (picked != null && widget.teams.contains(picked)) return picked;
    final mine = widget.eventController.myTeamNumber;
    if (mine != null && (widget.teams.isEmpty || widget.teams.contains(mine))) {
      return mine;
    }
    return widget.teams.isEmpty ? null : widget.teams.first;
  }

  int? _ratingRank(int team) {
    final rated =
        widget.eventController.displayTeams
            .where((t) => t.epa.totalPoints != null)
            .toList()
          ..sort((a, b) {
            final byEpa = b.epa.totalPoints!.compareTo(a.epa.totalPoints!);

            return byEpa != 0 ? byEpa : a.team.compareTo(b.team);
          });
    final index = rated.indexWhere((t) => t.team == team);
    return index < 0 ? null : index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.eventController;
    final team = _team;
    if (team == null) {
      return const EmptyState(
        icon: Icons.person_outline,
        message:
            'No team to follow yet.\n'
            'Set your team number in Settings to see its matches here.',
      );
    }

    final schedule = TeamMatchSchedule.build(
      team: team,
      sortedMatches: widget.matches,
      resultFor: controller.tbaMatchFor,
    );
    final ratingLabel = controller.teamsAreRosterOnly
        ? null
        : switch (controller.ratingsSource) {
            RatingsSource.match13 => 'xP rank',
            RatingsSource.statbotics => 'EPA rank',
            RatingsSource.none => null,
          };
    final hasResults = schedule.matches.any((m) => m.result != null);
    final stats = widget.eventStatsController;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TeamPicker(
            teams: widget.teams,
            selected: team,
            nicknames: controller.teamNicknames,
            onSelected: (value) => setState(() => _picked = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(
                label: 'Record',
                value: hasResults ? schedule.record : null,
              ),
              _Stat(label: 'Rank', value: _ordinal(stats?.rankFor(team))),
              if (ratingLabel != null)
                _Stat(label: ratingLabel, value: _ordinal(_ratingRank(team))),
              _Stat(
                label: 'Predicted rank',
                value: _ordinal(controller.predictedRankFor(team)),
              ),
            ],
          ),
          if (controller.forecastsLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );

    final cards = schedule.matches;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            padding:
                const EdgeInsets.all(16) +
                EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
            itemCount: 1 + (cards.isEmpty ? 1 : cards.length),
            itemBuilder: (context, index) {
              if (index == 0) return header;
              if (cards.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No matches for $team on the loaded schedule.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
                  ),
                );
              }
              final entry = cards[index - 1];
              final onOpen = widget.onOpenMatch;
              return _TeamMatchCard(
                entry: entry,
                team: team,
                nicknames: controller.teamNicknames,
                forecasts: controller.forecastsFor(entry.match.key),
                sourcesMissing: controller.forecastSourcesMissing,
                onTap: onOpen == null ? null : () => onOpen(entry.match),
              );
            },
          ),
        ),
      ),
    );
  }

  static String? _ordinal(int? rank) => rank == null ? null : '#$rank';
}

class _TeamPicker extends StatelessWidget {
  const _TeamPicker({
    required this.teams,
    required this.selected,
    required this.nicknames,
    required this.onSelected,
  });

  final List<int> teams;
  final int selected;
  final Map<int, String> nicknames;
  final ValueChanged<int> onSelected;

  String _label(int team) {
    final nick = nicknames[team];
    return nick == null || nick.isEmpty ? '$team' : '$team $nick';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DropdownMenu<int>(
        key: ValueKey<int>(selected),
        initialSelection: selected,
        width: constraints.maxWidth,
        label: const Text('Team'),
        enableFilter: true,
        requestFocusOnTap: true,
        leadingIcon: const Icon(Icons.search_rounded, size: 18),
        menuHeight: 360,
        onSelected: (value) {
          if (value != null) onSelected(value);
        },
        dropdownMenuEntries: <DropdownMenuEntry<int>>[
          for (final team in teams)
            DropdownMenuEntry<int>(value: team, label: _label(team)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: StrategyPalette.mutedTextOf(context),
            ),
          ),
          Text(
            value ?? '--',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMatchCard extends StatelessWidget {
  const _TeamMatchCard({
    required this.entry,
    required this.team,
    required this.nicknames,
    required this.forecasts,
    required this.sourcesMissing,
    this.onTap,
  });

  final TeamMatch entry;
  final int team;
  final Map<int, String> nicknames;
  final List<MatchForecast> forecasts;
  final Set<String> sourcesMissing;
  final VoidCallback? onTap;

  String? _status(BuildContext context) {
    final outcome = entry.outcome;
    if (outcome != null) {
      final word = switch (outcome) {
        TeamMatchOutcome.win => 'Won',
        TeamMatchOutcome.loss => 'Lost',
        TeamMatchOutcome.tie => 'Tied',
      };
      return '$word ${entry.ourScore} - ${entry.theirScore}';
    }
    final result = entry.result;
    final predicted = result?.predictedTime;
    final time = predicted ?? result?.scheduledTime;
    if (time == null) return null;
    final local = time.toLocal();
    final clock = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(local));
    final day = const <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][local.weekday - 1];
    return '${predicted != null ? 'Est. ' : ''}$day $clock';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status(context);
    final match = entry.match;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: entry.isPlayed
                          ? theme.textTheme.labelLarge
                          : theme.textTheme.bodySmall?.copyWith(
                              color: StrategyPalette.mutedTextOf(context),
                            ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              AllianceLine(
                label: 'Red',
                teams: match.redTeams,
                nicknames: nicknames,
                highlightTeam: team,
              ),
              const SizedBox(height: 4),
              AllianceLine(
                label: 'Blue',
                teams: match.blueTeams,
                nicknames: nicknames,
                highlightTeam: team,
              ),
              for (final source in MatchForecastSource.values) ...[
                const SizedBox(height: 10),
                MatchForecastRow(
                  source: source,
                  forecast: forecasts
                      .where((f) => f.source == source)
                      .firstOrNull,
                  unreachable: sourcesMissing.contains(source.label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
