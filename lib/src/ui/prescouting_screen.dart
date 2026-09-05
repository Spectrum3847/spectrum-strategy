import 'package:flutter/material.dart';

import '../scouting/models/prescout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/services/prescout_summary_stats.dart';
import '../scouting/services/scout_field_display.dart';
import '../scouting/state/prescout_config_controller.dart';
import '../scouting/state/prescouting_controller.dart';
import '../scouting/ui/scout_form_fields.dart';
import '../services/assistant/assistant_service.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/film_split_view.dart';
import '../widgets/film_video_pane.dart';
import 'analysis_view.dart' show formatStat;
import 'comment_digest_card.dart';

const Map<String, String> kPrescoutEvents = <String, String>{
  'chezyChamps': 'Chezy Champs',
};

const List<int> kPrescoutTeams = <int>[
  254,
  359,
  581,
  604,
  687,
  694,
  841,
  846,
  971,
  972,
  973,
  1540,
  1678,
  1868,
  2046,
  2073,
  2813,
  2910,
  3045,
  3256,
  4270,
  4414,
  4499,
  4698,
  5026,
  5199,
  5507,
  5940,
  6017,
  6036,
  6238,
  6647,
  6665,
  6800,
  7415,
  8229,
  9023,
  9032,
  9128,
  9408,
  9470,
  9496,
];

const int kPrescoutMatchesPerTeam = 5;

const String _videoUrlCode = 'videoUrl';

class PrescoutingScreen extends StatelessWidget {
  const PrescoutingScreen({
    required this.controller,
    required this.configController,
    this.assistant,
    this.filmEmbedSupported,
    super.key,
  });

  final PrescoutingController controller;
  final PrescoutConfigController configController;

  final AssistantService? assistant;

  final bool? filmEmbedSupported;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pre-Scouting'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(text: 'Instructions'),
              Tab(text: 'Data'),
              Tab(text: 'Summary'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            const _InstructionsTab(),
            _DataTab(
              controller: controller,
              configController: configController,
              filmEmbedSupported: filmEmbedSupported,
            ),
            _SummaryTab(controller: controller, assistant: assistant),
          ],
        ),
      ),
    );
  }
}

class _InstructionsTab extends StatelessWidget {
  const _InstructionsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Pick any robot and watch five of its matches: three '
          'qualification matches plus two playoff matches if the team '
          'made playoffs. Record one entry per watched match in the Data '
          'tab.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        _body(
          context,
          'A check icon next to a team in the Data tab\'s team dropdown '
          'means that team is fully prescouted (five matches recorded) '
          'and no longer accepts new entries.',
        ),
        _body(
          context,
          'Paste the match film into the record form\'s Video URL field and '
          'the screen splits, film on one side and the form on the other. '
          'Drag the bar between them to resize. Leave it blank and the form '
          'keeps the whole screen.',
        ),
        _heading(context, 'Auto'),
        _body(context, 'Record the auto path as consecutive steps:'),
        _bullet(context, 'Did they climb (L1)? How many seconds did it take?'),
        _bullet(
          context,
          'Starting position: Center Hub, Depot Dump, Depot Trench, '
          'Outpost Bump, or Outpost Trench.',
        ),
        _bullet(
          context,
          'Where they shot their auto: Center Hub, Depot Bump, Depot '
          'Trench, Outpost Bump, or Outpost Trench.',
        ),
        _bullet(context, 'Intaking locations: Depot or Neutral Zone.'),
        _bullet(context, 'Total fuel scored.'),
        _body(
          context,
          'If they cycled multiple times, repeat the shooting and '
          'intaking steps and mark how many times with #x.',
        ),
        _body(
          context,
          'Example: Depot trench, neutral zone 2x, depot trench 2x, '
          '47x fuel scored',
        ),
        _heading(context, 'Teleop'),
        _body(
          context,
          'Approximate how much fuel the robot scored into the hub. If '
          'they did not score fuel in the match, put a zero.',
        ),
        _body(
          context,
          'Approximate accuracy as a bare number without the percent '
          'sign: a robot intended to score about 100 that scored about '
          '50 has 50 accuracy.',
        ),
        _body(context, 'Use the comments to cover:'),
        _bullet(context, 'Cycle Timing: how fast they cycle fuel.'),
        _bullet(
          context,
          'Best scoring location: the fastest scoring level or location.',
        ),
        _bullet(
          context,
          'Defense: do they play defense, where, and how effectively.',
        ),
        _bullet(context, 'Passing: do they pass, and how effectively.'),
        _bullet(
          context,
          'Stealing: do they steal fuel from the other alliance side, '
          'and does it force opponents into the neutral zone.',
        ),
        _bullet(
          context,
          'Intaking and loading speed: how long to fill the hopper, '
          'jams, launcher accuracy, and fuel per second.',
        ),
        _bullet(
          context,
          'Fouls: pinning a robot for more than three seconds, taking '
          'greater than momentary control of or redirecting fuel, and '
          'intentionally ejecting game pieces.',
        ),
        _heading(context, 'Endgame'),
        _body(
          context,
          'Climb: record the side they climbed on (Depot or Trench) and '
          'the level (L1, L2, L3). Mention in the comments how long the '
          'climb took and whether they climbed early in the endgame.',
        ),
        _body(
          context,
          'Comments: add anything else useful for analyzing the team, '
          'such as which robot they defended and how well, and any fouls '
          'they picked up doing it.',
        ),
        _body(context, 'Watch for these issues across the event:'),
        _bullet(
          context,
          'Disconnects: the robot suddenly stops moving mid-match for no '
          'clear reason. Consistent disconnects rule a robot out of '
          'alliance selection, even when it plays well.',
        ),
        _bullet(
          context,
          'Yellow cards: issued by the head ref for egregious robot '
          'behavior or repeated rule violations. Review the match footage '
          'to find where and why, and note it in the comments.',
        ),
        _bullet(
          context,
          'Red cards: issued for the same reasons, or after two yellow '
          'cards. One stays with the team for the rest of the event, so '
          'watch for the carryover card rather than mistaking it for a '
          'fresh yellow, and give the reason in the comments.',
        ),
      ],
    );
  }

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _body(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: Theme.of(context).textTheme.bodyMedium),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PrescoutColumn {
  const _PrescoutColumn(this.group, this.label, this.code);

  final StrategyPhase? group;
  final String label;
  final String code;
}

const List<_PrescoutColumn> _kColumns = <_PrescoutColumn>[
  _PrescoutColumn(null, 'Scouter', ''),
  _PrescoutColumn(null, 'Event', 'watchedEvent'),
  _PrescoutColumn(null, 'Match #', 'matchNumber'),
  _PrescoutColumn(StrategyPhase.auton, 'Start Pos', 'startingPosition'),
  _PrescoutColumn(StrategyPhase.auton, 'Auto Fuel', 'autoFuelScored'),
  _PrescoutColumn(StrategyPhase.auton, 'Auto Climb (L1)', 'autoClimbL1'),
  _PrescoutColumn(StrategyPhase.auton, 'Auto Path', 'autoPath'),
  _PrescoutColumn(StrategyPhase.teleop, 'Teleop Fuel', 'teleopFuelScored'),
  _PrescoutColumn(StrategyPhase.teleop, 'Fuel Acc. (%)', 'fuelAccuracy'),
  _PrescoutColumn(StrategyPhase.teleop, 'Defense', 'defense'),
  _PrescoutColumn(StrategyPhase.teleop, 'Passer/Pusher', 'passerPusher'),
  _PrescoutColumn(StrategyPhase.endgame, 'Climb Pos', 'climbPosition'),
  _PrescoutColumn(StrategyPhase.endgame, 'Low Climb (L1)', 'lowClimbL1'),
  _PrescoutColumn(StrategyPhase.endgame, 'Mid Climb (L2)', 'middleClimbL2'),
  _PrescoutColumn(StrategyPhase.endgame, 'High Climb (L3)', 'highClimbL3'),
  _PrescoutColumn(StrategyPhase.endgame, 'Disconnects', 'disconnects'),
  _PrescoutColumn(StrategyPhase.endgame, 'Yellow Cards', 'yellowCards'),
  _PrescoutColumn(StrategyPhase.endgame, 'Red Cards', 'redCards'),
  _PrescoutColumn(null, 'Comments', 'comments'),
  _PrescoutColumn(null, 'Video', _videoUrlCode),
];

Color? _groupColor(StrategyPhase? group) {
  switch (group) {
    case StrategyPhase.auton:
      return StrategyPalette.auton;
    case StrategyPhase.teleop:
      return StrategyPalette.teleop;
    case StrategyPhase.endgame:
      return StrategyPalette.endgame;
    case null:
      return null;
  }
}

class _TeamStatus {
  const _TeamStatus({required this.count, this.starterName});

  final int count;

  final String? starterName;

  bool get isComplete => count >= kPrescoutMatchesPerTeam;
  bool get isStarted => count > 0;
}

class _DataTab extends StatefulWidget {
  const _DataTab({
    required this.controller,
    required this.configController,
    this.filmEmbedSupported,
  });

  final PrescoutingController controller;
  final PrescoutConfigController configController;

  final bool? filmEmbedSupported;

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  PrescoutingController get _controller => widget.controller;

  ScoutConfig get _config => widget.configController.config;

  String? _selectedEventKey;
  int? _selectedTeam;

  List<PrescoutEntry> _entriesForTeam(int team) {
    return _controller.entries
        .where((e) => e.teamNumber == team)
        .toList(growable: false);
  }

  List<int> get _dropdownTeams {
    final teams = <int>{
      ...kPrescoutTeams,
      ..._controller.entries.map((e) => e.teamNumber),
    }.toList()..sort();
    return teams;
  }

  _TeamStatus _statusFor(int team) {
    final entries = _entriesForTeam(team);
    if (entries.isEmpty) return const _TeamStatus(count: 0);

    final starter = entries.reduce(
      (a, b) => a.updatedAt.isBefore(b.updatedAt) ? a : b,
    );
    return _TeamStatus(
      count: entries.length,
      starterName: starter.authorDisplayName.isEmpty
          ? null
          : starter.authorDisplayName,
    );
  }

  bool get _canAddToSelectedTeam {
    final team = _selectedTeam;
    if (_selectedEventKey == null || team == null) return false;
    return !_statusFor(team).isComplete;
  }

  Future<void> _addRecord() async {
    final team = _selectedTeam;
    final eventKey = _selectedEventKey;
    if (team == null || eventKey == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _RecordFormPage(
          controller: _controller,
          config: _config,
          teamNumber: team,
          eventKey: eventKey,
          eventLabel: kPrescoutEvents[eventKey] ?? '',
          filmEmbedSupported: widget.filmEmbedSupported,
        ),
      ),
    );
  }

  void _openRecord(PrescoutEntry entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _isOwn(entry)
            ? _RecordFormPage(
                controller: _controller,
                config: _config,
                teamNumber: entry.teamNumber,
                eventKey: entry.eventKey,
                eventLabel: kPrescoutEvents[entry.eventKey] ?? '',
                entry: entry,
                filmEmbedSupported: widget.filmEmbedSupported,
              )
            : _RecordDetailPage(entry: entry, config: _config),
      ),
    );
  }

  Future<void> _confirmDelete(PrescoutEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete prescout record?'),
          content: Text(
            'This will remove the prescout record for team '
            '${entry.teamNumber}, including from the shared database.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final deleted = await _controller.deleteEntry(entry.id);
    if (!mounted) return;

    if (deleted &&
        _selectedTeam != null &&
        !_dropdownTeams.contains(_selectedTeam)) {
      setState(() => _selectedTeam = null);
    }
    if (deleted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _controller.lastError ??
              'Could not delete that record. It is still saved on this '
                  'device.',
        ),
      ),
    );
    _controller.clearLastError();
  }

  bool _isOwn(PrescoutEntry entry) {
    final uid = _controller.currentUserUid;
    return entry.authorUid.isEmpty || (uid != null && entry.authorUid == uid);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _controller,
        widget.configController,
      ]),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('prescout-event-dropdown'),
                      initialValue: _selectedEventKey,
                      decoration: const InputDecoration(
                        labelText: 'Event',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Select an event'),
                      items: <DropdownMenuItem<String>>[
                        for (final e in kPrescoutEvents.entries)
                          DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedEventKey = value;
                          _selectedTeam = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedEventKey == null)
              const Expanded(
                child: EmptyState(
                  icon: Icons.event_outlined,
                  message:
                      'Select an event above before recording prescout '
                      'data.',
                ),
              )
            else
              Expanded(child: _buildEventBody(context)),
          ],
        );
      },
    );
  }

  Widget _buildEventBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('prescout-team-dropdown'),
                  initialValue: _selectedTeam,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Team',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Select a team'),
                  items: <DropdownMenuItem<int>>[
                    for (final team in _dropdownTeams)
                      DropdownMenuItem<int>(
                        value: team,
                        child: _TeamDropdownLabel(
                          status: _statusFor(team),
                          team: team,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selectedTeam = value),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _canAddToSelectedTeam ? _addRecord : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add record'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedTeam == null
              ? const EmptyState(
                  icon: Icons.smart_display_outlined,
                  message: 'Select a team above to see its prescout records.',
                )
              : _TeamRecordTable(
                  team: _selectedTeam!,
                  entries: _entriesForTeam(_selectedTeam!),
                  config: _config,
                  isOwn: _isOwn,
                  onTap: _openRecord,
                  onDelete: _confirmDelete,
                ),
        ),
      ],
    );
  }
}

class _TeamDropdownLabel extends StatelessWidget {
  const _TeamDropdownLabel({required this.status, required this.team});

  final _TeamStatus status;
  final int team;

  @override
  Widget build(BuildContext context) {
    final suffix = status.isComplete
        ? ''
        : status.isStarted
        ? ' (incomplete - ${status.starterName ?? 'unknown scouter'})'
        : '';
    return Row(
      children: [
        Expanded(child: Text('$team$suffix', overflow: TextOverflow.ellipsis)),
        if (status.isComplete)
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
      ],
    );
  }
}

class _TeamRecordTable extends StatelessWidget {
  const _TeamRecordTable({
    required this.team,
    required this.entries,
    required this.config,
    required this.isOwn,
    required this.onTap,
    required this.onDelete,
  });

  final int team;
  final List<PrescoutEntry> entries;
  final ScoutConfig config;
  final bool Function(PrescoutEntry entry) isOwn;
  final void Function(PrescoutEntry entry) onTap;
  final void Function(PrescoutEntry entry) onDelete;

  ScoutConfigField? _fieldFor(String code) {
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }

  String _cellText(_PrescoutColumn column, PrescoutEntry entry) {
    if (column.code.isEmpty) {
      return entry.authorDisplayName.isEmpty
          ? 'Unknown'
          : entry.authorDisplayName;
    }
    final field = _fieldFor(column.code);
    final raw = entry.fieldValues[column.code];
    if (field?.type == ScoutFieldType.boolean) {
      return raw == true ? 'Yes' : 'No';
    }
    final text = displayFieldValue(field, raw);
    return text.isEmpty ? '--' : text;
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.smart_display_outlined,
        message: 'No prescout records yet for this team. Add one to start.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 56,
            columnSpacing: 16,
            columns: <DataColumn>[
              for (final column in _kColumns)
                DataColumn(
                  label: Text(
                    column.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _groupColor(column.group),
                    ),
                  ),
                ),
              const DataColumn(label: Text('')),
            ],
            rows: <DataRow>[
              for (final entry in entries)
                DataRow(
                  onSelectChanged: (_) => onTap(entry),
                  cells: <DataCell>[
                    for (final column in _kColumns)
                      DataCell(Text(_cellText(column, entry))),
                    DataCell(
                      isOwn(entry)
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Delete entry',
                              onPressed: () => onDelete(entry),
                            )
                          : const Icon(Icons.lock_outline_rounded, size: 18),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTab extends StatefulWidget {
  const _SummaryTab({required this.controller, this.assistant});

  final PrescoutingController controller;

  final AssistantService? assistant;

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final rows = PrescoutSummaryStats.build(
          widget.controller.entries,
          teamNumbers: kPrescoutTeams,
        );
        final query = _searchController.text.trim();
        final filtered = query.isEmpty
            ? rows
            : rows
                  .where((r) => r.teamNumber.toString().contains(query))
                  .toList(growable: false);

        final focused = filtered.length == 1
            ? filtered.single.teamNumber
            : null;
        final teamEntries = focused == null
            ? const <PrescoutEntry>[]
            : (widget.controller.entries
                  .where((e) => e.teamNumber == focused)
                  .toList()
                ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                key: const ValueKey('prescout-summary-search'),
                controller: _searchController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                decoration: const InputDecoration(
                  labelText: 'Search team',
                  hintText: 'e.g. 3847',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (filtered.isEmpty)
              const Expanded(
                child: EmptyState(
                  icon: Icons.grid_on_outlined,
                  message: 'No matching team.',
                ),
              )
            else if (focused == null)
              Expanded(child: _PrescoutSummaryGrid(rows: filtered))
            else
              Expanded(
                child: ListView(
                  key: const ValueKey('prescout-summary-team-detail'),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _PrescoutSummaryGrid(rows: filtered, shrinkWrap: true),
                    _TeamDigestSection(
                      assistant: widget.assistant,
                      teamNumber: focused,
                      entries: teamEntries,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PrescoutSummaryGrid extends StatelessWidget {
  const _PrescoutSummaryGrid({required this.rows, this.shrinkWrap = false});

  final List<PrescoutSummaryRow> rows;

  final bool shrinkWrap;

  static const double _cellWidth = 92;

  @override
  Widget build(BuildContext context) {
    final iqmAutoFractions = PrescoutSummaryStats.gradeFractions(
      rows,
      (r) => r.iqmAutoFuel,
    );
    final maxAutoFractions = PrescoutSummaryStats.gradeFractions(
      rows,
      (r) => r.maxAutoFuel,
    );
    final iqmTeleopFractions = PrescoutSummaryStats.gradeFractions(
      rows,
      (r) => r.iqmTeleopFuel,
    );
    final maxTeleopFractions = PrescoutSummaryStats.gradeFractions(
      rows,
      (r) => r.maxTeleopFuel,
    );

    final table = DataTable(
      headingRowHeight: 40,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 48,
      columnSpacing: 12,
      columns: const <DataColumn>[
        DataColumn(label: Text('Team')),
        DataColumn(label: Text('Matches')),
        DataColumn(label: Text('IQM Auto'), numeric: true),
        DataColumn(label: Text('Max Auto'), numeric: true),
        DataColumn(label: Text('IQM Teleop'), numeric: true),
        DataColumn(label: Text('Max Teleop'), numeric: true),
        DataColumn(label: Text('Fuel Acc.'), numeric: true),
        DataColumn(label: Text('Auto Climb'), numeric: true),
        DataColumn(label: Text('Low Climb'), numeric: true),
        DataColumn(label: Text('Mid Climb'), numeric: true),
        DataColumn(label: Text('High Climb'), numeric: true),
      ],
      rows: <DataRow>[
        for (final row in rows)
          DataRow(
            cells: <DataCell>[
              DataCell(Text('${row.teamNumber}')),
              DataCell(Text('${row.matchesRecorded}/$kPrescoutMatchesPerTeam')),
              DataCell(
                _GradedCell(
                  value: row.iqmAutoFuel,
                  fraction: iqmAutoFractions[row.teamNumber],
                  width: _cellWidth,
                ),
              ),
              DataCell(
                _GradedCell(
                  value: row.maxAutoFuel,
                  fraction: maxAutoFractions[row.teamNumber],
                  width: _cellWidth,
                ),
              ),
              DataCell(
                _GradedCell(
                  value: row.iqmTeleopFuel,
                  fraction: iqmTeleopFractions[row.teamNumber],
                  width: _cellWidth,
                ),
              ),
              DataCell(
                _GradedCell(
                  value: row.maxTeleopFuel,
                  fraction: maxTeleopFractions[row.teamNumber],
                  width: _cellWidth,
                ),
              ),
              DataCell(_RateCell(value: row.avgFuelAccuracy, isRate: false)),
              DataCell(_RateCell(value: row.autoClimbRate)),
              DataCell(_RateCell(value: row.lowClimbRate)),
              DataCell(_RateCell(value: row.middleClimbRate)),
              DataCell(_RateCell(value: row.highClimbRate)),
            ],
          ),
      ],
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: shrinkWrap ? table : SingleChildScrollView(child: table),
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
  const _RateCell({required this.value, this.isRate = true});

  final double? value;
  final bool isRate;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '--'
        : isRate
        ? '${(value! * 100).round()}%'
        : formatStat(value!);
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _RecordFormPage extends StatefulWidget {
  const _RecordFormPage({
    required this.controller,
    required this.config,
    required this.teamNumber,
    this.eventKey,
    this.eventLabel = '',
    this.entry,
    this.filmEmbedSupported,
  });

  final PrescoutingController controller;
  final ScoutConfig config;
  final int teamNumber;

  final String? eventKey;

  final String eventLabel;

  final PrescoutEntry? entry;

  final bool? filmEmbedSupported;

  @override
  State<_RecordFormPage> createState() => _RecordFormPageState();
}

class _RecordFormPageState extends State<_RecordFormPage> {
  Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _textControllers = {};
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _initValues(widget.entry);
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initValues(PrescoutEntry? entry) {
    _values = {};
    for (final field in widget.config.allFields) {
      final prefillEvent =
          entry == null &&
          field.code == 'watchedEvent' &&
          widget.eventLabel.isNotEmpty;
      _values[field.code] = prefillEvent
          ? widget.eventLabel
          : entry?.fieldValues[field.code] ?? field.effectiveDefault;
      if (field.type == ScoutFieldType.text ||
          field.type == ScoutFieldType.number) {
        final ctrl = TextEditingController(
          text: _values[field.code]?.toString() ?? '',
        );
        ctrl.addListener(() {
          _values[field.code] = ctrl.text;

          if (field.code == _videoUrlCode && mounted) setState(() {});
        });
        _textControllers[field.code] = ctrl;
      }
    }
  }

  void _setFieldValue(String code, dynamic value) {
    setState(() {
      _values[code] = value;
    });
  }

  Future<void> _save() async {
    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }

    final base = widget.entry ?? PrescoutEntry(teamNumber: widget.teamNumber);
    final saved = await widget.controller.saveEntry(
      base.copyWith(
        teamNumber: widget.teamNumber,
        eventKey: widget.entry == null
            ? (widget.eventKey ?? base.eventKey)
            : base.eventKey,
        fieldValues: Map<String, dynamic>.from(_values),
      ),
    );
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _statusIsError = true;
        _statusMessage =
            widget.controller.lastError ??
            'Could not save the prescout record for team '
                '${widget.teamNumber}.';
      });
      widget.controller.clearLastError();
      return;
    }
    Navigator.of(context).pop();
  }

  String get _videoUrl => (_values[_videoUrlCode] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final form = ListView(
      key: const ValueKey('prescout-record-form-list'),
      padding: const EdgeInsets.all(16),
      children: [
        ...widget.config.sections.map(
          (section) => ScoutFormSection(
            section: section,
            keyPrefix: 'prescout-field',
            values: _values,
            textControllers: _textControllers,
            onFieldChanged: _setFieldValue,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save record'),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 12),
          _buildStatusCard(),
        ],
        const SizedBox(height: 24),
      ],
    );

    final url = _videoUrl;
    return Scaffold(
      appBar: AppBar(title: Text('Team ${widget.teamNumber} record')),

      body: url.isEmpty
          ? form
          : FilmSplitView(
              primary: form,
              secondary: FilmVideoPane(
                url: url,
                embedSupported: widget.filmEmbedSupported,
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: _statusIsError
          ? StrategyPalette.surfaceStrongOf(context)
          : StrategyPalette.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _statusIsError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 16,
              color: _statusIsError
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _statusIsError
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordDetailPage extends StatelessWidget {
  const _RecordDetailPage({required this.entry, required this.config});

  final PrescoutEntry entry;
  final ScoutConfig config;

  String get _authorLabel {
    return entry.authorDisplayName.isNotEmpty
        ? entry.authorDisplayName
        : entry.authorUid.isNotEmpty
        ? entry.authorUid
        : 'Offline entry';
  }

  List<(String, String)> get _orderedValues {
    final fieldByCode = {for (final f in config.allFields) f.code: f};
    final present = entry.fieldValues.keys.toSet();
    final ordered = <String>[
      for (final field in config.allFields)
        if (present.contains(field.code)) field.code,
    ];
    final unknown = present.difference(ordered.toSet()).toList()..sort();
    return [
      for (final code in [...ordered, ...unknown])
        (
          fieldByCode[code]?.title ?? code,
          displayFieldValue(fieldByCode[code], entry.fieldValues[code]),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('Team ${entry.teamNumber} record'),
        actions: const [
          Icon(Icons.lock_outline_rounded, size: 18),
          SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DetailRow(label: 'Team', value: '${entry.teamNumber}'),
          _DetailRow(label: 'Scouted by', value: _authorLabel),
          const Divider(),
          Text('Recorded fields', style: muted),
          const SizedBox(height: 4),
          if (_orderedValues.isEmpty)
            Text('No fields recorded.', style: muted)
          else
            for (final row in _orderedValues)
              _DetailRow(label: row.$1, value: row.$2),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _TeamDigestSection extends StatelessWidget {
  const _TeamDigestSection({
    required this.assistant,
    required this.teamNumber,
    required this.entries,
  });

  final AssistantService? assistant;
  final int teamNumber;
  final List<PrescoutEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = PrescoutSummaryStats.notesForTeam(teamNumber, entries);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes.isNotEmpty)
            CommentDigestCard(
              assistant: assistant,
              teamNumber: teamNumber,
              eventKey: entries.isEmpty ? '' : entries.first.eventKey,
              notes: notes,
            ),
          const SizedBox(height: 12),
          Text(
            entries.length == 1
                ? 'Team $teamNumber: 1 record'
                : 'Team $teamNumber: ${entries.length} records',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              'Nobody has prescouted this team yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: StrategyPalette.mutedTextOf(context),
              ),
            )
          else
            for (final entry in entries) _TeamRecordSummaryCard(entry: entry),
        ],
      ),
    );
  }
}

class _TeamRecordSummaryCard extends StatelessWidget {
  const _TeamRecordSummaryCard({required this.entry});

  final PrescoutEntry entry;

  String _value(String code) =>
      (entry.fieldValues[code] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = _value('matchNumber');
    final event = _value('watchedEvent');
    final comments = _value(PrescoutSummaryStats.commentsCode);
    final author = entry.authorDisplayName.isEmpty
        ? 'unknown scouter'
        : entry.authorDisplayName;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              <String>[
                if (event.isNotEmpty) event,
                if (match.isNotEmpty) 'Match $match',
                author,
              ].join(' - '),
              style: theme.textTheme.labelMedium?.copyWith(
                color: StrategyPalette.mutedTextOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              <String>[
                'Auto fuel ${_valueOrDash('autoFuelScored')}',
                'Teleop fuel ${_valueOrDash('teleopFuelScored')}',
                'Accuracy ${_valueOrDash('fuelAccuracy')}',
              ].join('   '),
              style: theme.textTheme.bodySmall,
            ),
            if (comments.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comments, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  String _valueOrDash(String code) {
    final value = _value(code);
    return value.isEmpty ? '--' : value;
  }
}
