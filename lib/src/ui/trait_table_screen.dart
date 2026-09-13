import 'dart:async';

import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../scouting/models/team_analysis.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/event_controller.dart';
import '../state/failed_write_tracker.dart';
import '../state/trait_table_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/segment_label.dart';
import '../widgets/sync_status_pill.dart';
import 'trait_table_view.dart';

enum _AllianceFilter { both, red, blue }

class TraitTableScreen extends StatefulWidget {
  const TraitTableScreen({
    required this.controller,
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    this.canEdit = true,
    super.key,
  });

  final TraitTableController controller;
  final EventController eventController;

  final ScoutingController scoutingController;
  final ScoutConfigController configController;

  final bool canEdit;

  @override
  State<TraitTableScreen> createState() => _TraitTableScreenState();
}

class _TraitTableScreenState extends State<TraitTableScreen> {
  String? _selectedMatchKey;

  _AllianceFilter _filter = _AllianceFilter.both;

  @override
  void initState() {
    super.initState();
    widget.eventController.addListener(_pruneSelection);
  }

  @override
  void didUpdateWidget(TraitTableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventController != widget.eventController) {
      oldWidget.eventController.removeListener(_pruneSelection);
      widget.eventController.addListener(_pruneSelection);
      _pruneSelection();
    }
  }

  @override
  void dispose() {
    widget.eventController.removeListener(_pruneSelection);
    super.dispose();
  }

  void _pruneSelection() {
    final selected = _selectedMatchKey;
    if (selected == null) return;
    final stillListed = widget.eventController.matches.any(
      (m) => m.key == selected,
    );
    if (stillListed) return;
    setState(() => _selectedMatchKey = null);
    unawaited(widget.controller.selectMatch(eventKey: '', matchId: ''));
  }

  String _matchIdFor(StatboticsMatch match) {
    final prefix = '${widget.eventController.eventKey}_';
    return match.key.startsWith(prefix)
        ? match.key.substring(prefix.length)
        : match.key;
  }

  void _selectMatch(StatboticsMatch match) {
    setState(() => _selectedMatchKey = match.key);
    unawaited(
      widget.controller.selectMatch(
        eventKey: widget.eventController.eventKey,
        matchId: _matchIdFor(match),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        widget.eventController,
        widget.scoutingController,
      ]),
      builder: (context, _) {
        final event = widget.eventController;
        if (event.eventKey.isEmpty) {
          return const EmptyState(
            icon: Icons.table_chart_outlined,
            message:
                'Select an event in Settings to fill in a trait table '
                'for its matches.',
          );
        }
        final matches = event.matches;
        if (matches.isEmpty) {
          return const EmptyState(
            icon: Icons.table_chart_outlined,
            message:
                'No match schedule for this event yet. The trait table is '
                'filled in per match, so the schedule has to load first.',
          );
        }

        final selected = matches
            .where((m) => m.key == _selectedMatchKey)
            .firstOrNull;

        final weAreRed = selected == null
            ? null
            : _weAreRed(selected, event.myTeamNumber);

        final teamNumbers = selected == null
            ? const <int>[]
            : switch (_filter) {
                _AllianceFilter.both => <int>[
                  ...selected.redTeams,
                  ...selected.blueTeams,
                ],
                _AllianceFilter.red => selected.redTeams,
                _AllianceFilter.blue => selected.blueTeams,
              };

        final analyses = ScoutingAnalysis.aggregateByTeam(
          widget.scoutingController.entries,
          config: widget.configController.config,
        );

        return Column(
          children: [
            if (widget.controller.failedWrites.hasFailures)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TraitTableSyncPill(
                    failedWrites: widget.controller.failedWrites,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                key: ValueKey('${event.eventKey}:${selected?.key ?? ''}'),
                initialValue: selected?.key,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'Match',
                ),
                items: [
                  for (final match in matches)
                    DropdownMenuItem(
                      value: match.key,
                      child: Text(match.displayName),
                    ),
                ],
                onChanged: (key) {
                  final match = matches.where((m) => m.key == key).firstOrNull;
                  if (match != null) _selectMatch(match);
                },
              ),
            ),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<_AllianceFilter>(
                    segments: [
                      const ButtonSegment(
                        value: _AllianceFilter.both,
                        label: SegmentLabel('Both'),
                      ),
                      ButtonSegment(
                        value: _AllianceFilter.red,
                        label: SegmentLabel(_allianceLabel(weAreRed, true)),
                      ),
                      ButtonSegment(
                        value: _AllianceFilter.blue,
                        label: SegmentLabel(_allianceLabel(weAreRed, false)),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                ),
              ),
            if (selected != null && widget.canEdit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _GenerateDraftsButton(
                    controller: widget.controller,
                    onPressed: () => _generateDrafts(teamNumbers, analyses),
                  ),
                ),
              ),
            Expanded(
              child: TraitTableView(
                controller: widget.controller,
                teamNumbers: teamNumbers,
                analyses: analyses,
                canEdit: widget.canEdit,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateDrafts(
    List<int> teamNumbers,
    Map<int, TeamAnalysis> analyses,
  ) {
    final entries = widget.scoutingController.entries;
    return widget.controller.generateDrafts(
      teamNumbers: teamNumbers,
      analyses: analyses,
      notesByTeam: {
        for (final team in teamNumbers)
          team: ScoutingAnalysis.notesForTeam(team, entries),
      },
    );
  }
}

bool? _weAreRed(StatboticsMatch match, int? myTeamNumber) {
  if (myTeamNumber == null) return null;
  if (match.redTeams.contains(myTeamNumber)) return true;
  if (match.blueTeams.contains(myTeamNumber)) return false;
  return null;
}

String _allianceLabel(bool? weAreRed, bool isRed) {
  if (weAreRed == null) return isRed ? 'Red alliance' : 'Blue alliance';
  final isOurs = weAreRed == isRed;
  return isOurs ? 'Our alliance' : 'Their alliance';
}

class _GenerateDraftsButton extends StatelessWidget {
  const _GenerateDraftsButton({required this.controller, this.onPressed});

  final TraitTableController controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!controller.canGenerateDrafts) {
      return const SizedBox.shrink();
    }
    final generating = controller.isGeneratingDrafts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          icon: generating
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(generating ? 'Drafting...' : 'Draft this table'),
          onPressed: generating ? null : onPressed,
        ),
        for (final team in controller.draftErrorTeams)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Team $team: ${controller.draftErrorFor(team)}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _TraitTableSyncPill extends StatelessWidget {
  const _TraitTableSyncPill({required this.failedWrites});

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    final count = failedWrites.unlandedCount;
    return SyncStatusPill(
      label: '$count edit${count == 1 ? '' : 's'} not saved',
      icon: Icons.cloud_off_rounded,
      isFailure: true,
    );
  }
}
