import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scouting/services/match_prediction_stats.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/match_schedule_row.dart' show sortMatchesByCompLevel;
import 'analysis_view.dart' show formatStat;

class MatchPredictionView extends StatefulWidget {
  const MatchPredictionView({
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    super.key,
  });

  final EventController eventController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;

  @override
  State<MatchPredictionView> createState() => _MatchPredictionViewState();
}

class _MatchPredictionViewState extends State<MatchPredictionView> {
  final _matchNumberController = TextEditingController();
  final _redControllers = List.generate(3, (_) => TextEditingController());
  final _blueControllers = List.generate(3, (_) => TextEditingController());
  String? _matchLookupError;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      ..._redControllers,
      ..._blueControllers,
    ]) {
      controller.addListener(_onTeamsChanged);
    }
  }

  @override
  void dispose() {
    _matchNumberController.dispose();
    for (final controller in <TextEditingController>[
      ..._redControllers,
      ..._blueControllers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTeamsChanged() => setState(() {});

  List<int?> get _redTeamNumbers =>
      _redControllers.map(_parseTeam).toList(growable: false);
  List<int?> get _blueTeamNumbers =>
      _blueControllers.map(_parseTeam).toList(growable: false);

  static int? _parseTeam(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  void _loadFromMatchNumber() {
    final matchNumber = int.tryParse(_matchNumberController.text.trim());
    if (matchNumber == null) {
      setState(() => _matchLookupError = 'Enter a match number.');
      return;
    }
    final matches = sortMatchesByCompLevel(widget.eventController.matches);
    final match = matches
        .where((m) => m.isQualification && m.matchNumber == matchNumber)
        .firstOrNull;
    if (match == null) {
      setState(
        () => _matchLookupError =
            'No qualification match $matchNumber '
            'on the loaded schedule.',
      );
      return;
    }
    setState(() {
      _matchLookupError = null;
      for (var i = 0; i < 3; i++) {
        _redControllers[i].text = '${match.redTeams[i]}';
        _blueControllers[i].text = '${match.blueTeams[i]}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.eventController,
        widget.scoutingController,
        widget.configController,
      ]),
      builder: (context, _) {
        final redTeams = _redTeamNumbers.whereType<int>().toList(
          growable: false,
        );
        final blueTeams = _blueTeamNumbers.whereType<int>().toList(
          growable: false,
        );
        final ready = redTeams.length == 3 && blueTeams.length == 3;
        final result = ready
            ? MatchPredictionStats.build(
                redTeams: redTeams,
                blueTeams: blueTeams,
                scoutEntries: widget.scoutingController.entries,
                config: widget.configController.config,
              )
            : null;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Match prediction',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick a match number to pull its six teams, or type them '
                  'in directly. Each alliance total is its three teams\' '
                  'IQM Auto plus IQM Teleop, summed from scouting.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
                ),
                const SizedBox(height: 16),
                _MatchNumberRow(
                  controller: _matchNumberController,
                  onLoad: _loadFromMatchNumber,
                  error: _matchLookupError,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final red = _AllianceInput(
                      label: 'Red Alliance',
                      color: StrategyPalette.allianceRed,
                      controllers: _redControllers,
                      nicknames: widget.eventController.teamNicknames,
                    );
                    final blue = _AllianceInput(
                      label: 'Blue Alliance',
                      color: StrategyPalette.allianceBlue,
                      controllers: _blueControllers,
                      nicknames: widget.eventController.teamNicknames,
                    );
                    if (constraints.maxWidth < 560) {
                      return Column(
                        children: [red, const SizedBox(height: 12), blue],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: red),
                        const SizedBox(width: 12),
                        Expanded(child: blue),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (result == null)
                  const EmptyState(
                    icon: Icons.calculate_outlined,
                    message:
                        'Enter all three teams for each alliance to see a '
                        'prediction.',
                  )
                else
                  _PredictionResultView(
                    result: result,
                    nicknames: widget.eventController.teamNicknames,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _MatchNumberRow extends StatelessWidget {
  const _MatchNumberRow({
    required this.controller,
    required this.onLoad,
    required this.error,
  });

  final TextEditingController controller;
  final VoidCallback onLoad;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Match number',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(StrategyPalette.radiusSm),
                    ),
                  ),
                ),
                onSubmitted: (_) => onLoad(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Load match'),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _AllianceInput extends StatelessWidget {
  const _AllianceInput({
    required this.label,
    required this.color,
    required this.controllers,
    required this.nicknames,
  });

  final String label;
  final Color color;
  final List<TextEditingController> controllers;
  final Map<int, String> nicknames;

  @override
  Widget build(BuildContext context) {
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
            label,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < controllers.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == controllers.length - 1 ? 0 : 8,
              ),
              child: TextField(
                controller: controllers[i],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Team ${i + 1}',
                  isDense: true,
                  helperText: _nicknameFor(controllers[i]),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(StrategyPalette.radiusSm),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _nicknameFor(TextEditingController controller) {
    final team = int.tryParse(controller.text.trim());
    if (team == null) return null;
    return nicknames[team];
  }
}

class _PredictionResultView extends StatelessWidget {
  const _PredictionResultView({required this.result, required this.nicknames});

  final MatchPredictionResult result;
  final Map<int, String> nicknames;

  @override
  Widget build(BuildContext context) {
    final redLeads = result.red.total > result.blue.total;
    final blueLeads = result.blue.total > result.red.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _TotalCard(
                label: 'Red',
                color: StrategyPalette.allianceRed,
                total: result.red.total,
                leading: redLeads,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TotalCard(
                label: 'Blue',
                color: StrategyPalette.allianceBlue,
                total: result.blue.total,
                leading: blueLeads,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _BreakdownTable(
                title: 'Red breakdown',
                rows: result.red.teams,
                nicknames: nicknames,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BreakdownTable(
                title: 'Blue breakdown',
                rows: result.blue.teams,
                nicknames: nicknames,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.color,
    required this.total,
    required this.leading,
  });

  final String label;
  final Color color;
  final double total;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: leading ? 0.18 : 0.08),
        border: Border.all(color: color, width: leading ? 2 : 1),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            formatStat(total),
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(
            'Predicted total',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
          ),
        ],
      ),
    );
  }
}

class _BreakdownTable extends StatelessWidget {
  const _BreakdownTable({
    required this.title,
    required this.rows,
    required this.nicknames,
  });

  final String title;
  final List<MatchPredictionTeamRow> rows;
  final Map<int, String> nicknames;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
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
              dataRowMaxHeight: 48,
              columnSpacing: 16,
              columns: const <DataColumn>[
                DataColumn(label: Text('Team')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('IQM Auto'), numeric: true),
                DataColumn(label: Text('IQM Teleop'), numeric: true),
                DataColumn(label: Text('Total'), numeric: true),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(
                    cells: <DataCell>[
                      DataCell(Text('${row.teamNumber}')),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            nicknames[row.teamNumber] ?? '--',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(_fmt(row.iqmAuto))),
                      DataCell(Text(_fmt(row.iqmTeleop))),
                      DataCell(
                        Text(
                          formatStat(row.total),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _fmt(double? value) => value == null ? '--' : formatStat(value);
}
