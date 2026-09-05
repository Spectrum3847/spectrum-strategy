import 'package:flutter/material.dart';

import '../models/pick_list.dart';
import '../scouting/models/team_analysis.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../services/assistant/assistant_service.dart';
import '../state/event_controller.dart';
import '../state/pick_list_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/segment_label.dart';
import '../widgets/text_prompt.dart';
import 'analysis_view.dart';

enum _RankSort { iqmScore, consistency, epa, overall }

class PlayoffRankingScreen extends StatefulWidget {
  const PlayoffRankingScreen({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    this.pickListController,
    this.assistant,
    this.embedded = false,
    this.pitScoutingController,
    this.pitScoutConfigController,
    super.key,
  });

  final EventController eventController;
  final ScoutingController scoutingController;

  final ScoutConfigController configController;
  final PickListController? pickListController;

  final AssistantService? assistant;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  final bool embedded;

  @override
  State<PlayoffRankingScreen> createState() => _PlayoffRankingScreenState();
}

class _PlayoffRankingScreenState extends State<PlayoffRankingScreen> {
  _RankSort _sort = _RankSort.iqmScore;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: Listenable.merge([
        widget.eventController,
        widget.scoutingController,
      ]),
      builder: (context, _) => _body(context),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Playoff ranking')),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    if (!widget.eventController.hasEvent) {
      return const _EmptyState(
        icon: Icons.flag_outlined,
        message:
            'No event selected.\n'
            'Go to Settings and choose an event to load team data.',
      );
    }

    if (widget.eventController.isLoading &&
        widget.eventController.teamEvents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.eventController.error != null) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        message:
            'Could not load event data.\n${widget.eventController.error}\n\n'
            'Check the event in Settings and try again.',
        onRetry: widget.eventController.refresh,
      );
    }

    final teams = widget.eventController.teamEvents;
    if (teams.isEmpty) {
      final notice = widget.eventController.dataNotice;
      return _EmptyState(
        icon: Icons.group_outlined,
        message:
            notice ??
            'No Statbotics team stats for '
                '"${widget.eventController.eventKey}".',
        onRetry: widget.eventController.refresh,
      );
    }

    final analysisByTeam = ScoutingAnalysis.aggregateByTeam(
      widget.scoutingController.entries,
      config: widget.configController.config,
    );
    final nicknames = widget.eventController.teamNicknames;

    final rows = teams
        .map((te) {
          return _RankRow(
            teamEvent: te,
            nickname: nicknames[te.team],
            analysis: analysisByTeam[te.team],
          );
        })
        .toList(growable: false);

    final sorted = _sort == _RankSort.iqmScore
        ? _sortByIqmScore(rows)
        : _sort == _RankSort.consistency
        ? _sortByConsistency(rows)
        : _sort == _RankSort.overall
        ? _sortByOverall(rows)
        : _sortByEpa(rows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SortBar(sort: _sort, onChanged: (s) => setState(() => _sort = s)),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final list = ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: sorted.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _TableHeader(sort: _sort);
                      }
                      final row = sorted[index - 1];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TeamRow(
                            rank: index,
                            row: row,
                            pickListController: widget.pickListController,
                            scoutingController: widget.scoutingController,
                            configController: widget.configController,
                            assistant: widget.assistant,
                            eventKey: widget.eventController.eventKey,
                            pitScoutingController: widget.pitScoutingController,
                            pitScoutConfigController:
                                widget.pitScoutConfigController,
                          ),
                          if (index < sorted.length)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 40,
                              endIndent: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                        ],
                      );
                    },
                  );

                  const minTableWidth = 380.0;
                  if (constraints.maxWidth >= minTableWidth) {
                    return list;
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: minTableWidth, child: list),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  static List<_RankRow> _sortByIqmScore(List<_RankRow> rows) {
    final copy = rows.toList();
    copy.sort((a, b) {
      final sa = a.analysis?.iqmTotalScore ?? -1;
      final sb = b.analysis?.iqmTotalScore ?? -1;
      final bySc = sb.compareTo(sa);
      if (bySc != 0) return bySc;

      final da = a.analysis?.scoreStdDev ?? double.infinity;
      final db = b.analysis?.scoreStdDev ?? double.infinity;
      final byDev = da.compareTo(db);
      if (byDev != 0) return byDev;
      return a.teamEvent.team.compareTo(b.teamEvent.team);
    });
    return copy;
  }

  static List<_RankRow> _sortByConsistency(List<_RankRow> rows) {
    final scouted = rows.where((r) => r.analysis != null).toList();
    final unscouted = rows.where((r) => r.analysis == null).toList();
    scouted.sort((a, b) {
      final byDev = (a.analysis!.scoreStdDev).compareTo(
        b.analysis!.scoreStdDev,
      );
      if (byDev != 0) return byDev;
      final byScore = b.analysis!.iqmTotalScore.compareTo(
        a.analysis!.iqmTotalScore,
      );
      if (byScore != 0) return byScore;
      return a.teamEvent.team.compareTo(b.teamEvent.team);
    });
    unscouted.sort((a, b) => a.teamEvent.team.compareTo(b.teamEvent.team));
    return [...scouted, ...unscouted];
  }

  static List<_RankRow> _sortByEpa(List<_RankRow> rows) {
    final copy = rows.toList();
    copy.sort((a, b) {
      final ea = a.teamEvent.epa.totalPoints;
      final eb = b.teamEvent.epa.totalPoints;
      if (ea == null && eb == null) {
        return a.teamEvent.team.compareTo(b.teamEvent.team);
      }
      if (ea == null) return 1;
      if (eb == null) return -1;
      return eb.compareTo(ea);
    });
    return copy;
  }

  static List<_RankRow> _sortByOverall(List<_RankRow> rows) {
    final scouted = rows.where((r) => r.analysis != null).toList();
    final unscouted = rows.where((r) => r.analysis == null).toList();

    final byEfficiency = scouted.toList()
      ..sort(
        (a, b) =>
            b.analysis!.iqmTotalScore.compareTo(a.analysis!.iqmTotalScore),
      );

    final byReliability = scouted.toList()
      ..sort(
        (a, b) => a.analysis!.scoreStdDev.compareTo(b.analysis!.scoreStdDev),
      );

    final effRankOf = <_RankRow, int>{};
    final relRankOf = <_RankRow, int>{};
    for (var i = 0; i < scouted.length; i++) {
      effRankOf[byEfficiency[i]] = i + 1;
      relRankOf[byReliability[i]] = i + 1;
    }

    scouted.sort((a, b) {
      final ra = 0.6 * effRankOf[a]! + 0.4 * relRankOf[a]!;
      final rb = 0.6 * effRankOf[b]! + 0.4 * relRankOf[b]!;
      final byCombined = ra.compareTo(rb);
      if (byCombined != 0) return byCombined;
      return a.teamEvent.team.compareTo(b.teamEvent.team);
    });

    unscouted.sort((a, b) => a.teamEvent.team.compareTo(b.teamEvent.team));
    return [...scouted, ...unscouted];
  }
}

class _RankRow {
  const _RankRow({
    required this.teamEvent,
    required this.nickname,
    required this.analysis,
  });

  final StatboticsTeamEvent teamEvent;
  final String? nickname;
  final TeamAnalysis? analysis;
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onChanged});

  final _RankSort sort;
  final ValueChanged<_RankSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Text(
            'Sort by',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_RankSort>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                    value: _RankSort.iqmScore,
                    label: SegmentLabel('IQM score'),
                  ),
                  ButtonSegment(
                    value: _RankSort.consistency,
                    label: SegmentLabel('Consistency'),
                  ),
                  ButtonSegment(
                    value: _RankSort.epa,
                    label: SegmentLabel('EPA'),
                  ),
                  ButtonSegment(
                    value: _RankSort.overall,
                    label: SegmentLabel('Overall'),
                  ),
                ],
                selected: {sort},
                onSelectionChanged: (s) => onChanged(s.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.sort});

  final _RankSort sort;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = text.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('#', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text('Team', style: style)),
          SizedBox(
            width: 60,
            child: Text('IQM', style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: 64,
            child: Text('Std Dev', style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: 52,
            child: Text('EPA', style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: 48,
            child: Text('Scouted', style: style, textAlign: TextAlign.end),
          ),

          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.rank,
    required this.row,
    required this.pickListController,
    required this.scoutingController,
    required this.configController,
    this.assistant,
    this.eventKey = '',
    this.pitScoutingController,
    this.pitScoutConfigController,
  });

  final int rank;
  final _RankRow row;
  final PickListController? pickListController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final AssistantService? assistant;
  final String eventKey;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final a = row.analysis;
    final te = row.teamEvent;
    final epa = te.epa.totalPoints;
    final isTopThree = rank <= 3;

    final onTap = a != null
        ? () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TeamAnalysisScreen(
                controller: scoutingController,
                configController: configController,
                teamNumber: te.team,
                assistant: assistant,
                eventKey: eventKey,
                pitScoutingController: pitScoutingController,
                pitScoutConfigController: pitScoutConfigController,
              ),
            ),
          )
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Semantics(
                label: 'Rank $rank',
                child: SizedBox(
                  width: 32,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      fontWeight: isTopThree ? FontWeight.w700 : null,
                      color: isTopThree
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
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
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (row.nickname != null && row.nickname!.isNotEmpty)
                      Text(
                        row.nickname!,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              SizedBox(
                width: 60,
                child: Text(
                  a != null ? formatStat(a.iqmTotalScore) : '--',
                  textAlign: TextAlign.end,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: a != null
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),

              SizedBox(
                width: 64,
                child: Text(
                  a != null && a.entryCount >= 2
                      ? formatStat(a.scoreStdDev)
                      : '--',
                  textAlign: TextAlign.end,
                  style: text.bodySmall?.copyWith(
                    color: a != null && a.entryCount >= 2
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),

              SizedBox(
                width: 52,
                child: Text(
                  epa != null ? epa.toStringAsFixed(1) : '--',
                  textAlign: TextAlign.end,
                  style: text.bodySmall?.copyWith(
                    color: epa != null
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: epa != null ? FontWeight.w600 : null,
                  ),
                ),
              ),

              SizedBox(
                width: 48,
                child: Text(
                  a != null ? '${a.matchCount}' : '--',
                  textAlign: TextAlign.end,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),

              SizedBox(
                width: 44,
                child: pickListController != null
                    ? _AddToListButton(
                        teamNumber: te.team,
                        controller: pickListController!,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddToListButton extends StatelessWidget {
  const _AddToListButton({required this.teamNumber, required this.controller});

  final int teamNumber;
  final PickListController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Add to pick list',
      icon: const Icon(Icons.playlist_add_rounded),
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      onPressed: () => _pickList(context),
    );
  }

  Future<void> _pickList(BuildContext context) async {
    final lists = controller.lists
        .where((l) {
          final uid = controller.currentUserUid;
          return uid == null || l.authorUid.isEmpty || l.authorUid == uid;
        })
        .toList(growable: false);

    if (!context.mounted) return;
    final result = await showModalBottomSheet<_PickListChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) =>
          _PickListSheet(teamNumber: teamNumber, lists: lists),
    );
    if (result == null || !context.mounted) return;

    String listId;
    if (result.createNew) {
      final newName = await promptText(
        context,
        title: 'New pick list',
        hint: 'List name',
      );
      if (newName == null || !context.mounted) return;
      final newList = await controller.create(newName);
      if (newList == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create the pick list.')),
          );
        }
        return;
      }
      listId = newList.id;
    } else {
      listId = result.listId!;
    }
    await controller.addTeam(listId, teamNumber);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Team $teamNumber added to pick list.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _PickListChoice {
  const _PickListChoice({this.listId, this.createNew = false});
  final String? listId;
  final bool createNew;
}

class _PickListSheet extends StatelessWidget {
  const _PickListSheet({required this.teamNumber, required this.lists});

  final int teamNumber;
  final List<PickList> lists;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              'Add team $teamNumber to',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text(
                'No pick lists yet. Create one below.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final list in lists)
                  ListTile(
                    leading: const Icon(Icons.format_list_numbered_rounded),
                    title: Text(list.name),
                    subtitle: Text(
                      '${list.teamNumbers.length} '
                      '${list.teamNumbers.length == 1 ? 'team' : 'teams'}',
                    ),
                    onTap: () =>
                        Navigator.of(context)
                            .pop(_PickListChoice(listId: list.id)),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.add_rounded, color: scheme.primary),
                  title: Text(
                    'New list',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () =>
                      Navigator.of(context)
                          .pop(const _PickListChoice(createNew: true)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.onRetry});

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      message: message,
      actions: [
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
