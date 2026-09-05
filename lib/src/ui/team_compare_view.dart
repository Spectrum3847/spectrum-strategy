import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../scouting/services/scouting_analysis.dart';
import '../scouting/services/team_compare_stats.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_service.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import 'team_compare_ai_card.dart';

class TeamCompareView extends StatefulWidget {
  const TeamCompareView({
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    this.assistant,
    super.key,
  });

  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;

  final AssistantService? assistant;

  @override
  State<TeamCompareView> createState() => _TeamCompareViewState();
}

class _TeamCompareViewState extends State<TeamCompareView> {
  static const int _columnCount = 3;

  final List<TextEditingController> _controllers = <TextEditingController>[
    for (var i = 0; i < _columnCount; i++) TextEditingController(),
  ];

  final List<ValueNotifier<int?>> _teamNumbers = <ValueNotifier<int?>>[
    for (var i = 0; i < _columnCount; i++) ValueNotifier<int?>(null),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final teamNumber in _teamNumbers) {
      teamNumber.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.scoutingController,
        widget.configController,
        widget.eventController,
      ]),
      builder: (context, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _columnCount; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(
                  width: 340,
                  child: _CompareColumn(
                    controller: _controllers[i],
                    teamNumber: _teamNumbers[i],
                    scoutingController: widget.scoutingController,
                    configController: widget.configController,
                    eventController: widget.eventController,
                    assistant: widget.assistant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CompareColumn extends StatelessWidget {
  const _CompareColumn({
    required this.controller,
    required this.teamNumber,
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    required this.assistant,
  });

  final TextEditingController controller;
  final ValueNotifier<int?> teamNumber;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;
  final AssistantService? assistant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<int?>(
      valueListenable: teamNumber,
      builder: (context, team, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Team number',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => teamNumber.value = int.tryParse(value.trim()),
          ),
          const SizedBox(height: 12),
          if (team == null)
            Text(
              'Enter a team number to compare.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: _CompareColumnBody(
                  teamNumber: team,
                  scoutingController: scoutingController,
                  configController: configController,
                  eventController: eventController,
                  assistant: assistant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompareColumnBody extends StatelessWidget {
  const _CompareColumnBody({
    required this.teamNumber,
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    required this.assistant,
  });

  final int teamNumber;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;
  final AssistantService? assistant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final entries = scoutingController.entries;
    final config = configController.config;

    final rows = TeamCompareStats.rowsFor(teamNumber, entries, config: config);
    final teamName = _teamNameFor(teamNumber);

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'No scout entries for team $teamNumber yet.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final (auto, teleop) = TeamCompareStats.fuelSeries(rows);
    final notes = ScoutingAnalysis.notesForTeam(teamNumber, entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          teamName == null || teamName.isEmpty
              ? 'Team $teamNumber'
              : 'Team $teamNumber -- $teamName',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _CompareTable(rows: rows),
        const SizedBox(height: 12),
        _FuelGraph(auto: auto, teleop: teleop),
        TeamCompareAiCard(
          assistant: assistant,
          teamNumber: teamNumber,
          eventKey: eventController.eventKey,
          entries: entries,
          notes: notes,
          config: config,
        ),
      ],
    );
  }

  String? _teamNameFor(int teamNumber) {
    for (final team in eventController.displayTeams) {
      if (team.team == teamNumber) return team.teamName;
    }
    return null;
  }
}

typedef _CellText = String Function(TeamCompareRow row);

class _StatRow {
  const _StatRow(this.label, this.textOf);
  final String label;
  final _CellText textOf;
}

String _numberOrDash(double? value) =>
    value == null ? '--' : '${value.round()}';
String _percentOrDash(double? value) =>
    value == null ? '--' : '${value.round()}%';
String _boolOrDash(bool? value) =>
    value == null ? '--' : (value ? 'Yes' : 'No');

final List<_StatRow> _statRows = <_StatRow>[
  _StatRow('Match', (r) => r.matchLabel),
  _StatRow('Start', (r) => r.startingPosition),
  _StatRow('Auto fuel', (r) => _numberOrDash(r.autoFuel)),
  _StatRow('Auto climb', (r) => r.autoClimb),
  _StatRow('Teleop fuel', (r) => _numberOrDash(r.teleopFuel)),
  _StatRow('Fuel accuracy', (r) => _percentOrDash(r.fuelAccuracy)),
  _StatRow('Defense', (r) => _boolOrDash(r.defense)),
  _StatRow('Passer/pusher', (r) => _boolOrDash(r.passerPusher)),
  _StatRow('Climb pos.', (r) => r.climbPosition),
  _StatRow('Low climb', (r) => r.lowClimb),
  _StatRow('Mid climb', (r) => r.middleClimb),
  _StatRow('High climb', (r) => r.highClimb),
];

class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.rows});

  final List<TeamCompareRow> rows;

  static const double _labelWidth = 100;
  static const double _colWidth = 76;
  static const double _rowHeight = 30;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Column(
            children: [
              for (final stat in _statRows)
                _Cell(
                  text: stat.label,
                  height: _rowHeight,
                  alignRight: false,
                  bold: true,
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final row in rows)
                  SizedBox(
                    width: _colWidth,
                    child: Column(
                      children: [
                        for (final stat in _statRows)
                          _Cell(
                            text: stat.textOf(row),
                            height: _rowHeight,
                            alignRight: true,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.height,
    required this.alignRight,
    this.bold = false,
  });

  final String text;
  final double height;
  final bool alignRight;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: StrategyPalette.borderOf(context)),
        ),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _FuelGraph extends StatelessWidget {
  const _FuelGraph({required this.auto, required this.teleop});

  final List<double?> auto;
  final List<double?> teleop;

  @override
  Widget build(BuildContext context) {
    final autoColor = StrategyPalette.phaseColor(StrategyPhase.auton);
    final teleopColor = StrategyPalette.phaseColor(StrategyPhase.teleop);
    final text = Theme.of(context).textTheme;

    if (auto.every((v) => v == null) && teleop.every((v) => v == null)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No fuel data yet.',
          style: text.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: autoColor, label: 'Auto'),
            const SizedBox(width: 16),
            _LegendDot(color: teleopColor, label: 'Teleop'),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 140,
          width: double.infinity,
          child: CustomPaint(
            painter: _FuelGraphPainter(
              auto: auto,
              teleop: teleop,
              gridColor: StrategyPalette.borderOf(context),
              autoColor: autoColor,
              teleopColor: teleopColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _FuelGraphPainter extends CustomPainter {
  _FuelGraphPainter({
    required this.auto,
    required this.teleop,
    required this.gridColor,
    required this.autoColor,
    required this.teleopColor,
  });

  final List<double?> auto;
  final List<double?> teleop;
  final Color gridColor;
  final Color autoColor;
  final Color teleopColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (auto.isEmpty) return;

    const top = 8.0;
    const left = 4.0;
    final bottom = size.height - 8;
    final right = size.width - 4;
    final maxValue = _maxOf([...auto, ...teleop]);
    final count = auto.length;
    final dx = count > 1 ? (right - left) / (count - 1) : 0.0;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = top + (bottom - top) * i / 2;
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);
    }

    _drawSeries(canvas, auto, autoColor, left, dx, top, bottom, maxValue);
    _drawSeries(canvas, teleop, teleopColor, left, dx, top, bottom, maxValue);
  }

  void _drawSeries(
    Canvas canvas,
    List<double?> values,
    Color color,
    double left,
    double dx,
    double top,
    double bottom,
    double maxValue,
  ) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        previous = null;
        continue;
      }
      final x = left + dx * i;
      final y = bottom - (value / maxValue) * (bottom - top);
      final point = Offset(x, y);
      if (previous != null) canvas.drawLine(previous, point, linePaint);
      canvas.drawCircle(point, 2.5, dotPaint);
      previous = point;
    }
  }

  static double _maxOf(List<double?> values) {
    var max = 0.0;
    for (final value in values) {
      if (value != null && value > max) max = value;
    }
    return max == 0 ? 1 : max;
  }

  @override
  bool shouldRepaint(covariant _FuelGraphPainter oldDelegate) =>
      !listEquals(auto, oldDelegate.auto) ||
      !listEquals(teleop, oldDelegate.teleop) ||
      gridColor != oldDelegate.gridColor ||
      autoColor != oldDelegate.autoColor ||
      teleopColor != oldDelegate.teleopColor;
}
