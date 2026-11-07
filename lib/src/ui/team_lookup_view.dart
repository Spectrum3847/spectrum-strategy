import 'package:flutter/material.dart';

import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/services/entry_match.dart';
import '../scouting/services/scout_field_display.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/services/team_summary_stats.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_service.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import 'analysis_view.dart' show formatStat;
import 'comment_digest_card.dart';
import 'database_tab.dart' show teamNumberFieldCodes;

class TeamLookupView extends StatefulWidget {
  const TeamLookupView({
    required this.scoutingController,
    required this.configController,
    this.eventController,
    this.assistant,
    this.canPublishSummaries = false,
    super.key,
  });

  final ScoutingController scoutingController;
  final ScoutConfigController configController;

  final EventController? eventController;

  final AssistantService? assistant;

  final bool canPublishSummaries;

  @override
  State<TeamLookupView> createState() => _TeamLookupViewState();
}

class _TeamLookupViewState extends State<TeamLookupView> {
  final TextEditingController _teamNumber = TextEditingController();

  @override
  void dispose() {
    _teamNumber.dispose();
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
        final team = int.tryParse(_teamNumber.text.trim());
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: TextField(
                    controller: _teamNumber,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Team number',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: team == null
                  ? const EmptyState(
                      icon: Icons.search_rounded,
                      message:
                          'Type a team number to see its summary, scouting '
                          'history, and trends.',
                    )
                  : _TeamLookupBody(
                      teamNumber: team,
                      entries: widget.scoutingController.entries,
                      config: widget.configController.config,
                      assistant: widget.assistant,
                      eventKey: widget.eventController?.eventKey ?? '',
                      canPublishSummaries: widget.canPublishSummaries,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TeamLookupBody extends StatelessWidget {
  const _TeamLookupBody({
    required this.teamNumber,
    required this.entries,
    required this.config,
    required this.assistant,
    required this.eventKey,
    this.canPublishSummaries = false,
  });

  final int teamNumber;
  final List<ScoutEntry> entries;
  final ScoutConfig? config;
  final AssistantService? assistant;
  final String eventKey;
  final bool canPublishSummaries;

  @override
  Widget build(BuildContext context) {
    final row = TeamSummaryStats.build(
      entries,
      teamNumbers: <int>[teamNumber],
      config: config,
    ).firstWhere((r) => r.teamNumber == teamNumber);

    final history =
        entries
            .where(
              (e) =>
                  e.teamNumber == teamNumber &&
                  (eventKey.isEmpty ||
                      eventKeyOfEntry(e) == null ||
                      eventKeyOfEntry(e) == eventKey),
            )
            .toList()
          ..sort(_compareByMatchThenCreatedAt);

    final notes = ScoutingAnalysis.notesForTeam(teamNumber, entries);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Team $teamNumber',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Summary'),
            const SizedBox(height: 8),
            _SummaryGrid(row: row),
            const SizedBox(height: 24),
            _SectionLabel(
              history.isEmpty
                  ? 'Scouting history'
                  : 'Scouting history (${history.length})',
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              Text(
                'No scouting entries recorded for this team yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              _ScoutingHistoryTable(entries: history, config: config),

            if (notes.isNotEmpty && eventKey.isNotEmpty) ...[
              const SizedBox(height: 24),
              _SectionLabel('Trends'),
              const SizedBox(height: 8),
              CommentDigestCard(
                assistant: assistant,
                teamNumber: teamNumber,
                eventKey: eventKey,
                notes: notes,
                canPublish: canPublishSummaries,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

int _compareByMatchThenCreatedAt(ScoutEntry a, ScoutEntry b) {
  final aNumber = matchNumberOfEntry(a);
  final bNumber = matchNumberOfEntry(b);
  if (aNumber == null || bNumber == null) {
    return a.createdAt.compareTo(b.createdAt);
  }
  return aNumber.compareTo(bNumber);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.row});

  final TeamSummaryRow row;

  static const _fourColumnMinWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String)>[
      ('IQM Teleop', _stat(row.iqmTeleop)),
      ('Max Teleop', _stat(row.maxTeleop)),
      ('IQM Auto', _stat(row.iqmAuto)),
      ('Max Auto', _stat(row.maxAuto)),
      ('Auto Climb', _rate(row.autoClimbRate)),
      ('Low Climb', _rate(row.lowClimbRate)),
      ('Mid Climb', _rate(row.middleClimbRate)),
      ('High Climb', _rate(row.highClimbRate)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= _fourColumnMinWidth ? 4 : 2;
        return Column(
          children: [
            for (var i = 0; i < stats.length; i += columns) ...[
              if (i > 0) const SizedBox(height: 8),

              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + columns; j++) ...[
                      if (j > i) const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryTile(
                          label: stats[j].$1,
                          value: stats[j].$2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _stat(double? value) =>
      value == null ? '--' : formatStat(value);

  static String _rate(double? value) =>
      value == null ? '--' : '${(value * 100).round()}%';
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ScoutingHistoryTable extends StatelessWidget {
  const _ScoutingHistoryTable({required this.entries, required this.config});

  final List<ScoutEntry> entries;
  final ScoutConfig? config;

  List<String> _columnCodes() {
    final allFields = config?.allFields ?? const <ScoutConfigField>[];
    final allKeys = <String>{};
    for (final entry in entries) {
      allKeys.addAll(entry.fieldValues.keys);
    }
    final configOrder = [for (final field in allFields) field.code];
    final orderedKeys = [
      for (final code in configOrder)
        if (allKeys.contains(code)) code,
    ];
    final unknownKeys = allKeys.difference(orderedKeys.toSet()).toList()
      ..sort();
    return [...orderedKeys, ...unknownKeys];
  }

  String _cellText(ScoutEntry entry, String key, ScoutConfigField? field) {
    final stored = entry.fieldValues[key];
    final storedIsZero = stored is num && stored == 0;
    if ((stored == null || storedIsZero) &&
        teamNumberFieldCodes.contains(key) &&
        entry.teamNumber > 0) {
      return entry.teamNumber.toString();
    }
    return displayFieldValue(field, stored);
  }

  @override
  Widget build(BuildContext context) {
    final fieldByCode = {
      for (final field in config?.allFields ?? const <ScoutConfigField>[])
        field.code: field,
    };
    final columns = _columnCodes();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final headerStyle = text.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 56,
        columnSpacing: 20,
        columns: [
          for (final code in columns)
            DataColumn(
              label: Text(fieldByCode[code]?.title ?? code, style: headerStyle),
            ),

          DataColumn(label: Text('Notes', style: headerStyle)),
        ],
        rows: [
          for (final entry in entries)
            DataRow(
              cells: [
                for (final code in columns)
                  DataCell(
                    Text(
                      _cellText(entry, code, fieldByCode[code]),
                      style: text.bodySmall,
                    ),
                  ),
                DataCell(Text(entry.notes, style: text.bodySmall)),
              ],
            ),
        ],
      ),
    );
  }
}
