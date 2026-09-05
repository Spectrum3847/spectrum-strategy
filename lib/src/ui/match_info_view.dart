import 'package:flutter/material.dart';

import '../models/playoff_board.dart';
import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/team_analysis.dart';
import '../scouting/services/match_info_stats.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_service.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/match_schedule_row.dart' show sortMatchesByCompLevel;
import 'analysis_view.dart' show formatStat;
import 'comment_digest_card.dart';

class MatchInfoView extends StatelessWidget {
  const MatchInfoView({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    this.pitScoutingController,
    this.pitScoutConfigController,
    this.assistant,
    super.key,
  });

  final EventController eventController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  final AssistantService? assistant;

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      eventController,
      scoutingController,
      configController,
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
                'Select an event to load the match schedule.',
          );
        }

        final myTeamNumber = eventController.myTeamNumber;
        if (myTeamNumber == null) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            message:
                'No team number set.\n'
                'Set your team number in Settings to build match info.',
          );
        }

        final matches = sortMatchesByCompLevel(eventController.matches);
        final entries = MatchInfoStats.build(
          matches: matches,
          myTeamNumber: myTeamNumber,
          scoutEntries: scoutingController.entries,
          config: configController.config,
          pitConfig: pitScoutConfigController?.config,
          teamNames: eventController.teamNicknames,
          pitEntryByTeam: mostRecentPitEntryByTeam(pitScouting?.entries),
        );

        if (entries.isEmpty) {
          return EmptyState(
            icon: Icons.calendar_month_outlined,
            message:
                eventController.scheduleError ??
                'No matches for team $myTeamNumber yet.\n'
                    'Load the event schedule to build match info.',
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) => _MatchInfoCard(
                entry: entries[index],
                eventKey: eventController.eventKey,
                assistant: assistant,
                notesForTeam: (team) => ScoutingAnalysis.notesForTeam(
                  team,
                  scoutingController.entries,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Map<int, PitScoutEntry> mostRecentPitEntryByTeam(List<PitScoutEntry>? entries) {
  if (entries == null || entries.isEmpty) return const <int, PitScoutEntry>{};
  final byTeam = <int, PitScoutEntry>{};
  for (final entry in entries) {
    final existing = byTeam[entry.teamNumber];
    if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
      byTeam[entry.teamNumber] = entry;
    }
  }
  return byTeam;
}

class _MatchInfoCard extends StatelessWidget {
  const _MatchInfoCard({
    required this.entry,
    required this.eventKey,
    required this.assistant,
    required this.notesForTeam,
  });

  final MatchInfoEntry entry;
  final String eventKey;
  final AssistantService? assistant;
  final List<TeamNote> Function(int teamNumber) notesForTeam;

  static const double _sideBySideBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = <MatchInfoRow>[...entry.preMatch, ...entry.opponents];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.match.displayName,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final preMatch = MatchInfoRowsTable(
                  title: 'Pre-match',
                  rows: entry.preMatch,
                );
                final opponents = MatchInfoRowsTable(
                  title: 'Opponents',
                  rows: entry.opponents,
                );
                if (constraints.maxWidth < _sideBySideBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [preMatch, const SizedBox(height: 16), opponents],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: preMatch),
                    const SizedBox(width: 16),
                    Expanded(child: opponents),
                  ],
                );
              },
            ),
            if (rows.any((r) => notesForTeam(r.teamNumber).isNotEmpty)) ...[
              const SizedBox(height: 16),
              Text(
                'Notes',
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final row in rows)
                _TeamNotesBlock(
                  row: row,
                  eventKey: eventKey,
                  assistant: assistant,
                  notes: notesForTeam(row.teamNumber),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class MatchInfoColumn {
  const MatchInfoColumn({
    required this.label,
    required this.code,
    required this.read,
    this.numeric = false,
    this.width = 72,
  });

  final String label;
  final String code;
  final String Function(MatchInfoRow row) read;
  final bool numeric;
  final double width;
}

String _fmtStat(double? value) => value == null ? '--' : formatStat(value);

final List<MatchInfoColumn> matchInfoColumns = <MatchInfoColumn>[
  MatchInfoColumn(
    label: 'Name',
    code: 'name',
    read: (row) => row.teamName ?? '--',
    width: 120,
  ),
  MatchInfoColumn(
    label: 'Robot type',
    code: 'robotType',
    read: (row) => row.robotType.isEmpty ? '--' : row.robotType,
    width: 160,
  ),
  MatchInfoColumn(
    label: 'Max Auto',
    code: 'maxAuto',
    read: (row) => _fmtStat(row.maxAuto),
    numeric: true,
  ),
  MatchInfoColumn(
    label: 'IQM Auto',
    code: 'iqmAuto',
    read: (row) => _fmtStat(row.iqmAuto),
    numeric: true,
  ),
  MatchInfoColumn(
    label: 'Teleop',
    code: 'teleop',
    read: (row) => _fmtStat(row.teleopAverage),
    numeric: true,
  ),
  MatchInfoColumn(
    label: 'IQM Fuel',
    code: 'iqmFuel',
    read: (row) => _fmtStat(row.iqmFuel),
    numeric: true,
  ),
  MatchInfoColumn(
    label: 'Max Teleop',
    code: 'maxTeleop',
    read: (row) => _fmtStat(row.maxTeleop),
    numeric: true,
  ),
  MatchInfoColumn(
    label: 'Climb',
    code: 'climb',
    read: (row) => row.everClimbedAutoL1 ? 'L1' : '',
  ),
];

class MatchInfoRowsTable extends StatelessWidget {
  const MatchInfoRowsTable({
    required this.title,
    required this.rows,
    this.tableId = '',
    this.overrides = const <String, String>{},
    this.onCellEdited,
    super.key,
  });

  final String title;
  final List<MatchInfoRow> rows;

  final String tableId;

  final Map<String, String> overrides;

  final void Function(String key, String value)? onCellEdited;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final editable = onCellEdited != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text(
            'Teams not set for this match.',
            style: text.bodySmall?.copyWith(color: muted),
          )
        else
          Container(
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
                dataRowMaxHeight: editable ? 60 : 48,
                columnSpacing: 16,
                columns: <DataColumn>[
                  const DataColumn(label: Text('Team')),
                  for (final column in matchInfoColumns)
                    DataColumn(
                      label: Text(column.label),
                      numeric: column.numeric,
                    ),
                ],
                rows: <DataRow>[
                  for (final row in rows)
                    DataRow(
                      cells: <DataCell>[
                        DataCell(Text('${row.teamNumber}')),
                        for (final column in matchInfoColumns)
                          DataCell(_cell(row, column)),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cell(MatchInfoRow row, MatchInfoColumn column) {
    final computed = column.read(row);
    final onEdited = onCellEdited;
    if (onEdited == null) {
      return SizedBox(
        width: column.width,
        child: Text(computed, overflow: TextOverflow.ellipsis),
      );
    }
    final key = PlayoffBoard.overrideKey(
      tableId: tableId,
      teamNumber: row.teamNumber,
      columnCode: column.code,
    );
    return _EditableStatCell(
      cellKey: ValueKey<String>(key),
      width: column.width,
      hint: computed,
      value: overrides[key] ?? '',
      onChanged: (value) => onEdited(key, value),
    );
  }
}

class _EditableStatCell extends StatefulWidget {
  const _EditableStatCell({
    required this.cellKey,
    required this.width,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final ValueKey<String> cellKey;
  final double width;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_EditableStatCell> createState() => _EditableStatCellState();
}

class _EditableStatCellState extends State<_EditableStatCell> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_EditableStatCell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.value != _controller.text && !_hasFocus) {
      _controller.text = widget.value;
    }
  }

  bool _hasFocus = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Focus(
        onFocusChange: (hasFocus) => _hasFocus = hasFocus,
        child: TextField(
          key: widget.cellKey,
          controller: _controller,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: widget.hint,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

class _TeamNotesBlock extends StatelessWidget {
  const _TeamNotesBlock({
    required this.row,
    required this.eventKey,
    required this.assistant,
    required this.notes,
  });

  final MatchInfoRow row;
  final String eventKey;
  final AssistantService? assistant;
  final List<TeamNote> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final label = (row.teamName == null || row.teamName!.isEmpty)
        ? 'Team ${row.teamNumber}'
        : 'Team ${row.teamNumber} · ${row.teamName}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelLarge),
          const SizedBox(height: 4),
          CommentDigestCard(
            assistant: assistant,
            teamNumber: row.teamNumber,
            eventKey: eventKey,
            notes: notes,
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                notes.length == 1
                    ? 'All 1 comment'
                    : 'All ${notes.length} comments',
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              children: [for (final note in notes) _NoteTile(note: note)],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final TeamNote note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final noteContext = <String>[
      if (note.matchId.isNotEmpty) 'Match ${note.matchId}',
      if (note.phase != null) note.phase!.label,
      if (note.author.isNotEmpty) note.author,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.text, style: text.bodySmall),
          if (noteContext.isNotEmpty)
            Text(noteContext, style: text.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}
