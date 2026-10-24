import 'package:flutter/material.dart';

import '../../models/match_preview.dart';
import '../../scouting/services/match_hub_stats.dart';
import '../../scouting/services/start_position_conflicts.dart';
import '../../theme/strategy_palette.dart';
import '../match_info_view.dart' show MatchInfoColumn, matchInfoColumns;

@visibleForTesting
const List<String> matchHubStatTableCodes = <String>[
  'robotType',
  'iqmAuto',
  'iqmFuel',
  'endgameClimb',
];

class StartConflictNotice extends StatelessWidget {
  const StartConflictNotice({required this.conflicts, super.key});

  final List<StartConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final conflict in conflicts) Text(conflict.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchHubStatTable extends StatelessWidget {
  const MatchHubStatTable({
    required this.data,
    required this.onOpenTeam,
    super.key,
  });

  final MatchHubData data;
  final ValueChanged<int> onOpenTeam;

  static const double _teamWidth = 88;
  static const double _columnWidth = 120;

  @override
  Widget build(BuildContext context) {
    final columns = <MatchInfoColumn>[
      for (final code in matchHubStatTableCodes)
        for (final column in matchInfoColumns)
          if (column.code == code) column,
    ];
    final border = StrategyPalette.borderOf(context);
    final teams = <MatchPreviewTeam>[...data.preview.red, ...data.preview.blue];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: border),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: <int, TableColumnWidth>{
          0: const FixedColumnWidth(_teamWidth),
          for (var i = 1; i <= columns.length; i++)
            i: const FixedColumnWidth(_columnWidth),
        },
        children: <TableRow>[
          TableRow(
            decoration: BoxDecoration(
              color: StrategyPalette.surfaceOf(context),
            ),
            children: <Widget>[
              const _Cell('Team', bold: true),
              for (final column in columns) _Cell(column.label, bold: true),
            ],
          ),
          for (final team in teams)
            TableRow(
              children: <Widget>[
                _TeamCell(team: team, onOpenTeam: onOpenTeam),
                for (final column in columns) _Cell(_read(column, team)),
              ],
            ),
        ],
      ),
    );
  }

  String _read(MatchInfoColumn column, MatchPreviewTeam team) {
    final row = data.rows[team.teamNumber];
    final text = row == null ? '' : column.read(row);
    return text.isEmpty ? '--' : text;
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: bold ? FontWeight.w700 : null),
      ),
    );
  }
}

class _TeamCell extends StatelessWidget {
  const _TeamCell({required this.team, required this.onOpenTeam});

  final MatchPreviewTeam team;
  final ValueChanged<int> onOpenTeam;

  @override
  Widget build(BuildContext context) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.fill,
      child: Semantics(
        button: true,
        label: 'Open team ${team.teamNumber}',
        excludeSemantics: true,
        child: Material(
          color: StrategyPalette.allianceColor(team.isRed ? 'Red' : 'Blue'),
          child: InkWell(
            onTap: () => onOpenTeam(team.teamNumber),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: Text(
                  '${team.teamNumber}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: StrategyPalette.onAlliance,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
