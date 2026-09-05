import 'package:flutter/material.dart';

import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/services/entry_match.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/services/team_summary_stats.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_service.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import 'analysis_view.dart' show formatDate, formatStat;
import 'comment_digest_card.dart';

class TeamLookupView extends StatefulWidget {
  const TeamLookupView({
    required this.scoutingController,
    required this.configController,
    this.eventController,
    this.assistant,
    super.key,
  });

  final ScoutingController scoutingController;
  final ScoutConfigController configController;

  final EventController? eventController;

  final AssistantService? assistant;

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
  });

  final int teamNumber;
  final List<ScoutEntry> entries;
  final ScoutConfig? config;
  final AssistantService? assistant;
  final String eventKey;

  @override
  Widget build(BuildContext context) {
    final row = TeamSummaryStats.build(
      entries,
      teamNumbers: <int>[teamNumber],
      config: config,
    ).firstWhere((r) => r.teamNumber == teamNumber);

    final history = entries.where((e) => e.teamNumber == teamNumber).toList()
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
            _SummaryList(row: row),
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
              for (final entry in history)
                _EntryHistoryCard(entry: entry, config: config),

            if (notes.isNotEmpty && eventKey.isNotEmpty) ...[
              const SizedBox(height: 24),
              _SectionLabel('Trends'),
              const SizedBox(height: 8),
              CommentDigestCard(
                assistant: assistant,
                teamNumber: teamNumber,
                eventKey: eventKey,
                notes: notes,
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

class _SummaryList extends StatelessWidget {
  const _SummaryList({required this.row});

  final TeamSummaryRow row;

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
    return Container(
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: StrategyPalette.borderOf(context)),
            _SummaryListRow(label: stats[i].$1, value: stats[i].$2),
          ],
        ],
      ),
    );
  }

  static String _stat(double? value) =>
      value == null ? '--' : formatStat(value);

  static String _rate(double? value) =>
      value == null ? '--' : '${(value * 100).round()}%';
}

class _SummaryListRow extends StatelessWidget {
  const _SummaryListRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EntryHistoryCard extends StatelessWidget {
  const _EntryHistoryCard({required this.entry, required this.config});

  final ScoutEntry entry;
  final ScoutConfig? config;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final fields = _fieldSummaries(entry, config);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                matchLabelOfEntry(entry),
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${entry.effectiveAlliance} · ${formatDate(entry.createdAt)}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final field in fields)
                  Text(
                    '${field.$1}: ${field.$2}',
                    style: text.bodySmall?.copyWith(color: scheme.onSurface),
                  ),
              ],
            ),
          ],
          if (entry.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(entry.notes.trim(), style: text.bodySmall),
          ],
        ],
      ),
    );
  }

  static const _identityCodes = <String>{'pTnumber', 'matchNumber', 'robot'};

  static List<(String, String)> _fieldSummaries(
    ScoutEntry entry,
    ScoutConfig? config,
  ) {
    final byCode = Map<String, dynamic>.of(entry.fieldValues);
    for (final code in _identityCodes) {
      byCode.remove(code);
    }
    final result = <(String, String)>[];
    if (config != null) {
      for (final field in config.allFields) {
        if (!byCode.containsKey(field.code)) continue;
        final raw = byCode.remove(field.code);
        final label = field.labelForStored(raw);
        if (label.isEmpty) continue;
        result.add((field.title, label));
      }
    }
    for (final leftover in byCode.entries) {
      final label = leftover.value?.toString() ?? '';
      if (label.isEmpty) continue;
      result.add((leftover.key, label));
    }
    return result;
  }
}
