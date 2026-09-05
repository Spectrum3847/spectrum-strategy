import 'package:flutter/material.dart';

import '../models/playoff_board.dart';
import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/services/playoff_match_info_stats.dart';
import '../scouting/services/robot_type.dart';
import '../scouting/services/scouting_meeting_stats.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/event_controller.dart';
import '../state/playoff_board_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/match_schedule_row.dart' show sortMatchesByCompLevel;
import 'analysis_view.dart' show formatStat;
import 'match_info_view.dart' show MatchInfoRowsTable, mostRecentPitEntryByTeam;

enum _PlayoffView {
  matchInfo('Match info', Icons.event_note_outlined),
  meeting('Scouting meeting', Icons.groups_2_outlined),
  alliances('Alliances', Icons.handshake_outlined);

  const _PlayoffView(this.label, this.icon);

  final String label;
  final IconData icon;
}

class PlayoffSectionScreen extends StatefulWidget {
  const PlayoffSectionScreen({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    required this.boardController,
    this.pitScoutingController,
    this.pitScoutConfigController,
    super.key,
  });

  final EventController eventController;
  final ScoutingController scoutingController;

  final ScoutConfigController configController;

  final PlayoffBoardController boardController;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  @override
  State<PlayoffSectionScreen> createState() => _PlayoffSectionScreenState();
}

class _PlayoffSectionScreenState extends State<PlayoffSectionScreen> {
  _PlayoffView _view = _PlayoffView.matchInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlayoffViewBar(
          selected: _view,
          onChanged: (view) => setState(() => _view = view),
        ),
        Expanded(
          child: IndexedStack(
            index: _view.index,
            sizing: StackFit.expand,
            children: [
              _PlayoffMatchInfoView(
                eventController: widget.eventController,
                scoutingController: widget.scoutingController,
                configController: widget.configController,
                boardController: widget.boardController,
                pitScoutingController: widget.pitScoutingController,
                pitScoutConfigController: widget.pitScoutConfigController,
              ),
              _ScoutingMeetingView(
                scoutingController: widget.scoutingController,
                configController: widget.configController,
                eventController: widget.eventController,
                boardController: widget.boardController,
                pitScoutingController: widget.pitScoutingController,
                pitScoutConfigController: widget.pitScoutConfigController,
              ),
              _AlliancesDetailView(
                scoutingController: widget.scoutingController,
                configController: widget.configController,
                eventController: widget.eventController,
                boardController: widget.boardController,
                pitScoutingController: widget.pitScoutingController,
                pitScoutConfigController: widget.pitScoutConfigController,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayoffViewBar extends StatelessWidget {
  const _PlayoffViewBar({required this.selected, required this.onChanged});

  final _PlayoffView selected;
  final ValueChanged<_PlayoffView> onChanged;

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<_PlayoffView>(
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          segments: [
            for (final view in _PlayoffView.values)
              ButtonSegment(
                value: view,
                label: Text(view.label),
                icon: Icon(view.icon, size: 16),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}

class _PlayoffMatchInfoView extends StatelessWidget {
  const _PlayoffMatchInfoView({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    required this.boardController,
    this.pitScoutingController,
    this.pitScoutConfigController,
  });

  final EventController eventController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final PlayoffBoardController boardController;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      eventController,
      scoutingController,
      configController,
      boardController,
    ];
    final pitScouting = pitScoutingController;
    if (pitScouting != null) listenables.add(pitScouting);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        if (!eventController.hasEvent) {
          return const EmptyState(
            icon: Icons.flag_outlined,
            message:
                'No event selected.\n'
                'Select an event to load the playoff schedule.',
          );
        }

        final myTeamNumber = eventController.myTeamNumber;
        if (myTeamNumber == null) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            message:
                'No team number set.\n'
                'Set your team number in Settings to build playoff match info.',
          );
        }

        final matches = sortMatchesByCompLevel(eventController.matches);
        final pitEntryByTeam = mostRecentPitEntryByTeam(pitScouting?.entries);
        final allianceRows = PlayoffMatchInfoStats.allianceRowsFor(
          matches: matches,
          myTeamNumber: myTeamNumber,
          scoutEntries: scoutingController.entries,
          config: configController.config,
          pitConfig: pitScoutConfigController?.config,
          teamNames: eventController.teamNicknames,
          pitEntryByTeam: pitEntryByTeam,
        );
        final entries = PlayoffMatchInfoStats.build(
          matches: matches,
          myTeamNumber: myTeamNumber,
          scoutEntries: scoutingController.entries,
          config: configController.config,
          pitConfig: pitScoutConfigController?.config,
          teamNames: eventController.teamNicknames,
          pitEntryByTeam: pitEntryByTeam,
        );

        final eventKey = eventController.eventKey;
        final board = boardController.boardFor(eventKey);

        if (entries.isEmpty) {
          return EmptyState(
            icon: Icons.calendar_month_outlined,
            message:
                'No playoff matches for team $myTeamNumber yet.\n'
                'Playoff match info appears once the bracket is set.',
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MatchInfoRowsTable(
                      title: 'Our alliance',
                      rows: allianceRows,
                      tableId: 'alliance',
                      overrides: board.matchInfoOverrides,
                      onCellEdited: (key, value) => boardController
                          .setMatchInfoOverride(eventKey, key, value),
                    ),
                  ),
                ),
                for (final entry in entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.match.displayName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          MatchInfoRowsTable(
                            title: 'Opponents',
                            rows: entry.opponents,
                            tableId: entry.match.key,
                            overrides: board.matchInfoOverrides,
                            onCellEdited: (key, value) => boardController
                                .setMatchInfoOverride(eventKey, key, value),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScoutingMeetingView extends StatelessWidget {
  const _ScoutingMeetingView({
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    required this.boardController,
    this.pitScoutingController,
    this.pitScoutConfigController,
  });

  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;
  final PlayoffBoardController boardController;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      scoutingController,
      configController,
      eventController,
      boardController,
    ];
    final pitScouting = pitScoutingController;
    if (pitScouting != null) listenables.add(pitScouting);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final rankedTeams = ScoutingMeetingStats.rankedTeams(
          scoutEntries: scoutingController.entries,
          config: configController.config,
          teamNames: eventController.teamNicknames,
        );
        final eventKey = eventController.eventKey;

        if (eventKey.isEmpty) {
          return const EmptyState(
            icon: Icons.flag_outlined,
            message:
                'No event selected.\n'
                'Select an event to open the scouting meeting board.',
          );
        }

        final tankTeams = ScoutingMeetingStats.tankDrivetrainTeams(
          pitEntryByTeam: mostRecentPitEntryByTeam(pitScouting?.entries),
          pitConfig: pitScoutConfigController?.config,
        );
        final cardedTeams = ScoutingMeetingStats.cardedTeams(
          scoutingController.entries,
        );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MeetingBoardGrid(
                    board: boardController.boardFor(eventKey),
                    onCellChanged: (row, column, value) => boardController
                        .setMeetingCell(eventKey, row, column, value),
                    onLabelChanged: (column, label) =>
                        boardController.setColumnLabel(eventKey, column, label),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final ranked = rankedTeams.isEmpty
                          ? const _NoRankedTeamsNotice()
                          : _RankedTeamList(rows: rankedTeams);
                      final side = _TeamNumberPanel(
                        title: 'Tank drivetrain',
                        icon: Icons.compare_arrows_rounded,
                        teamNumbers: tankTeams,
                        emptyMessage: 'No tank-drivetrain teams pit scouted.',
                      );
                      final cards = _TeamNumberPanel(
                        title: 'Yellow / red card',
                        icon: Icons.warning_amber_rounded,
                        teamNumbers: cardedTeams,
                        emptyMessage: 'No cards recorded.',
                      );
                      if (constraints.maxWidth < 700) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ranked,
                            const SizedBox(height: 16),
                            side,
                            const SizedBox(height: 16),
                            cards,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: ranked),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                side,
                                const SizedBox(height: 16),
                                cards,
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MeetingBoardGrid extends StatelessWidget {
  const _MeetingBoardGrid({
    required this.board,
    required this.onCellChanged,
    required this.onLabelChanged,
  });

  final PlayoffBoard board;
  final void Function(int row, int column, String value) onCellChanged;
  final void Function(int column, String label) onLabelChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sorting board',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'Best to worst, left to right. Rename a column by typing over its '
          'label.',
          style: text.bodySmall?.copyWith(
            color: StrategyPalette.mutedTextOf(context),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (
                    var column = 0;
                    column < PlayoffBoard.meetingColumnCount;
                    column++
                  )
                    _GridCellField(
                      cellKey: ValueKey<String>('meeting-label-$column'),
                      value: board.columnLabel(column),
                      hint: 'Column ${column + 1}',
                      bold: true,
                      onChanged: (value) => onLabelChanged(column, value),
                    ),
                ],
              ),
              for (var row = 0; row < PlayoffBoard.meetingRowCount; row++)
                Row(
                  children: [
                    for (
                      var column = 0;
                      column < PlayoffBoard.meetingColumnCount;
                      column++
                    )
                      _GridCellField(
                        cellKey: ValueKey<String>('meeting-$row-$column'),
                        value: board.meetingCell(row, column),
                        onChanged: (value) => onCellChanged(row, column, value),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AllianceGrid extends StatelessWidget {
  const _AllianceGrid({required this.board, required this.onCellChanged});

  final PlayoffBoard board;
  final void Function(int row, int column, String value) onCellChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alliances',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _GridHeaderCell(label: 'Alliance', width: 72),
                  for (final label in PlayoffBoard.allianceColumnLabels)
                    _GridHeaderCell(label: label),
                ],
              ),
              for (var row = 0; row < PlayoffBoard.allianceRowCount; row++)
                Row(
                  children: [
                    _GridHeaderCell(label: '${row + 1}', width: 72),
                    for (
                      var column = 0;
                      column < PlayoffBoard.allianceColumnCount;
                      column++
                    )
                      _GridCellField(
                        cellKey: ValueKey<String>('alliance-$row-$column'),
                        value: board.allianceCell(row, column),
                        onChanged: (value) => onCellChanged(row, column, value),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridHeaderCell extends StatelessWidget {
  const _GridHeaderCell({required this.label, this.width = 96});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _GridCellField extends StatefulWidget {
  const _GridCellField({
    required this.cellKey,
    required this.value,
    required this.onChanged,
    this.hint,
    this.bold = false,
  });

  static const double cellWidth = 96;

  final ValueKey<String> cellKey;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool bold;

  @override
  State<_GridCellField> createState() => _GridCellFieldState();
}

class _GridCellFieldState extends State<_GridCellField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  bool _hasFocus = false;

  @override
  void didUpdateWidget(_GridCellField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.value != _controller.text && !_hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _GridCellField.cellWidth,
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
      ),
      child: Focus(
        onFocusChange: (hasFocus) => _hasFocus = hasFocus,
        child: TextField(
          key: widget.cellKey,
          controller: _controller,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: widget.bold ? FontWeight.w700 : FontWeight.w400,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: widget.hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 8,
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

class _NoRankedTeamsNotice extends StatelessWidget {
  const _NoRankedTeamsNotice();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No scouted teams yet. The ranked list fills in once scout entries '
      'come in.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
    );
  }
}

class _RankedTeamList extends StatelessWidget {
  const _RankedTeamList({required this.rows});

  final List<RankedTeamRow> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: 20,
          columns: const <DataColumn>[
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Team')),
            DataColumn(label: Text('IQM auto'), numeric: true),
            DataColumn(label: Text('IQM teleop'), numeric: true),
          ],
          rows: <DataRow>[
            for (var i = 0; i < rows.length; i++)
              DataRow(
                cells: <DataCell>[
                  DataCell(Text('${i + 1}')),
                  DataCell(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rows[i].teamNumber}',
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (rows[i].teamName != null &&
                            rows[i].teamName!.isNotEmpty)
                          Text(rows[i].teamName!, style: text.bodySmall),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      rows[i].iqmAuto == null
                          ? '--'
                          : formatStat(rows[i].iqmAuto!),
                    ),
                  ),
                  DataCell(
                    Text(
                      rows[i].iqmTeleop == null
                          ? '--'
                          : formatStat(rows[i].iqmTeleop!),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TeamNumberPanel extends StatelessWidget {
  const _TeamNumberPanel({
    required this.title,
    required this.icon,
    required this.teamNumbers,
    required this.emptyMessage,
  });

  final String title;
  final IconData icon;
  final List<int> teamNumbers;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (teamNumbers.isEmpty)
            Text(
              emptyMessage,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final team in teamNumbers)
                  Chip(
                    label: Text('$team'),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        StrategyPalette.radiusSm,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AlliancesDetailView extends StatelessWidget {
  const _AlliancesDetailView({
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    required this.boardController,
    this.pitScoutingController,
    this.pitScoutConfigController,
  });

  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;
  final PlayoffBoardController boardController;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  static const int _panelCount = 3;

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      scoutingController,
      configController,
      eventController,
      boardController,
    ];
    final pitScouting = pitScoutingController;
    if (pitScouting != null) listenables.add(pitScouting);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final eventKey = eventController.eventKey;
        if (eventKey.isEmpty) {
          return const EmptyState(
            icon: Icons.flag_outlined,
            message:
                'No event selected.\n'
                'Select an event to open the alliance grid.',
          );
        }

        final board = boardController.boardFor(eventKey);
        final rankedTeams = ScoutingMeetingStats.rankedTeams(
          scoutEntries: scoutingController.entries,
          config: configController.config,
          teamNames: eventController.teamNicknames,
        );
        final rowByTeam = <int, RankedTeamRow>{
          for (final row in rankedTeams) row.teamNumber: row,
        };
        final panelTeams = board.meetingTeamsInReadingOrder
            .take(_panelCount)
            .toList(growable: false);
        final pitEntryByTeam = mostRecentPitEntryByTeam(pitScouting?.entries);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AllianceGrid(
                    board: board,
                    onCellChanged: (row, column, value) => boardController
                        .setAllianceCell(eventKey, row, column, value),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Top of the sorting board',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (panelTeams.isEmpty)
                    Text(
                      'Fill in the scouting meeting board and its first three '
                      'teams show up here.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StrategyPalette.mutedTextOf(context),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final team in panelTeams)
                          SizedBox(
                            width: 280,
                            child: _TeamDetailPanel(
                              row:
                                  rowByTeam[team] ??
                                  RankedTeamRow(
                                    teamNumber: team,
                                    teamName:
                                        eventController.teamNicknames[team],
                                  ),
                              pitEntry: pitEntryByTeam[team],
                              pitConfig: pitScoutConfigController?.config,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TeamDetailPanel extends StatelessWidget {
  const _TeamDetailPanel({required this.row, this.pitEntry, this.pitConfig});

  final RankedTeamRow row;
  final PitScoutEntry? pitEntry;
  final ScoutConfig? pitConfig;

  ScoutConfigField? get _driveTrainField {
    final config = pitConfig;
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == RobotType.driveTrainCode) return field;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final robotType = RobotType.composeFrom(
      pitEntry,
      driveTrainField: _driveTrainField,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row.teamNumber}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (row.teamName != null && row.teamName!.isNotEmpty)
            Text(
              row.teamName!,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          Text(
            'IQM auto: ${row.iqmAuto == null ? '--' : formatStat(row.iqmAuto!)}',
            style: text.bodySmall,
          ),
          Text(
            'IQM teleop: '
            '${row.iqmTeleop == null ? '--' : formatStat(row.iqmTeleop!)}',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          Text('Pit scouting', style: text.labelMedium),
          Text(
            robotType.isEmpty ? 'No pit entry yet.' : robotType,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
