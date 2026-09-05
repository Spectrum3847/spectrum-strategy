import 'package:flutter/material.dart';

import '../scouting/services/scouting_analysis.dart';
import '../scouting/services/team_summary_stats.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import 'analysis_view.dart' show formatStat;

class TeamSummaryView extends StatefulWidget {
  const TeamSummaryView({
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    super.key,
  });

  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;

  @override
  State<TeamSummaryView> createState() => _TeamSummaryViewState();
}

class _TeamSummaryViewState extends State<TeamSummaryView> {
  int? _sortColumn;
  bool _sortDescending = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.scoutingController,
        widget.configController,
        widget.eventController,
      ]),
      builder: (context, _) {
        final teamNumbers = <int>{
          ...widget.eventController.displayTeams.map((t) => t.team),
          ...ScoutingAnalysis.teamNumbers(widget.scoutingController.entries),
        };
        final rows = TeamSummaryStats.build(
          widget.scoutingController.entries,
          teamNumbers: teamNumbers,
          config: widget.configController.config,
        );

        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.grid_on_outlined,
            message:
                'No teams to summarize yet.\n'
                'Select an event or scan a scout entry to populate this '
                'table.',
          );
        }

        return _SummaryGrid(
          rows: _sortedRows(rows),
          sortColumn: _sortColumn,
          sortDescending: _sortDescending,
          onSort: _onSort,
        );
      },
    );
  }

  void _onSort(int? column) {
    setState(() {
      if (column == _sortColumn) {
        _sortDescending = !_sortDescending;
      } else {
        _sortColumn = column;

        _sortDescending = column != null;
      }
    });
  }

  List<TeamSummaryRow> _sortedRows(List<TeamSummaryRow> rows) {
    final column = _sortColumn;
    final sorted = rows.toList(growable: false);
    if (column == null) {
      sorted.sort((a, b) => a.teamNumber.compareTo(b.teamNumber));
      return sorted;
    }
    final getter = _summaryColumns[column].getter;
    sorted.sort((a, b) {
      final va = getter(a);
      final vb = getter(b);

      if (va == null && vb == null) return a.teamNumber.compareTo(b.teamNumber);
      if (va == null) return 1;
      if (vb == null) return -1;
      final byValue = _sortDescending ? vb.compareTo(va) : va.compareTo(vb);
      if (byValue != 0) return byValue;
      return a.teamNumber.compareTo(b.teamNumber);
    });
    return sorted;
  }
}

typedef _ValueGetter = double? Function(TeamSummaryRow row);

class _SummaryColumn {
  const _SummaryColumn(this.label, this.getter, {this.graded = false});

  final String label;
  final _ValueGetter getter;
  final bool graded;
}

const List<_SummaryColumn> _summaryColumns = <_SummaryColumn>[
  _SummaryColumn('IQM Teleop', _iqmTeleop, graded: true),
  _SummaryColumn('Max Teleop', _maxTeleop, graded: true),
  _SummaryColumn('IQM Auto', _iqmAuto, graded: true),
  _SummaryColumn('Max Auto', _maxAuto, graded: true),
  _SummaryColumn('Auto Climb', _autoClimbRate),
  _SummaryColumn('Low Climb', _lowClimbRate),
  _SummaryColumn('Mid Climb', _middleClimbRate),
  _SummaryColumn('High Climb', _highClimbRate),
];

double? _iqmTeleop(TeamSummaryRow r) => r.iqmTeleop;
double? _maxTeleop(TeamSummaryRow r) => r.maxTeleop;
double? _iqmAuto(TeamSummaryRow r) => r.iqmAuto;
double? _maxAuto(TeamSummaryRow r) => r.maxAuto;
double? _autoClimbRate(TeamSummaryRow r) => r.autoClimbRate;
double? _lowClimbRate(TeamSummaryRow r) => r.lowClimbRate;
double? _middleClimbRate(TeamSummaryRow r) => r.middleClimbRate;
double? _highClimbRate(TeamSummaryRow r) => r.highClimbRate;

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.rows,
    required this.sortColumn,
    required this.sortDescending,
    required this.onSort,
  });

  final List<TeamSummaryRow> rows;
  final int? sortColumn;
  final bool sortDescending;
  final ValueChanged<int?> onSort;

  static const double _cellWidth = 88;

  @override
  Widget build(BuildContext context) {
    final fractions = <int, Map<int, double>>{
      for (var i = 0; i < _summaryColumns.length; i++)
        if (_summaryColumns[i].graded)
          i: TeamSummaryStats.gradeFractions(rows, _summaryColumns[i].getter),
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 48,
          columnSpacing: 12,
          sortColumnIndex: sortColumn == null ? 0 : sortColumn! + 1,
          sortAscending: sortColumn == null ? true : !sortDescending,
          columns: <DataColumn>[
            DataColumn(
              label: const Text('Team'),
              onSort: (_, _) => onSort(null),
            ),
            for (var i = 0; i < _summaryColumns.length; i++)
              DataColumn(
                label: SizedBox(
                  width: _cellWidth,
                  child: Text(
                    _summaryColumns[i].label,
                    textAlign: TextAlign.right,
                  ),
                ),
                numeric: true,
                onSort: (_, _) => onSort(i),
              ),
          ],
          rows: <DataRow>[
            for (final row in rows)
              DataRow(
                cells: <DataCell>[
                  DataCell(Text('${row.teamNumber}')),
                  for (var i = 0; i < _summaryColumns.length; i++)
                    DataCell(
                      _summaryColumns[i].graded
                          ? _GradedCell(
                              value: _summaryColumns[i].getter(row),
                              fraction: fractions[i]?[row.teamNumber],
                              width: _cellWidth,
                            )
                          : _RateCell(
                              value: _summaryColumns[i].getter(row),
                              width: _cellWidth,
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

class _GradedCell extends StatelessWidget {
  const _GradedCell({
    required this.value,
    required this.fraction,
    required this.width,
  });

  final double? value;
  final double? fraction;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '--' : formatStat(value!);
    if (fraction == null) {
      return SizedBox(
        width: width,
        child: Text(text, textAlign: TextAlign.right),
      );
    }
    final background = StrategyPalette.gradeColorOf(context, fraction!);
    final ink = StrategyPalette.onGradeColorOf(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      alignment: Alignment.centerRight,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(color: ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RateCell extends StatelessWidget {
  const _RateCell({required this.value, required this.width});

  final double? value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '--' : '${(value! * 100).round()}%';
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
