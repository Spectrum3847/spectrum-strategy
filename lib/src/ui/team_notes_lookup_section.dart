import 'package:flutter/material.dart';

import '../models/trex_trait_report.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/team_lookup_summary.dart';
import '../services/team_lookup_notes.dart';
import '../state/trex_trait_report_controller.dart';
import '../theme/strategy_palette.dart';
import 'match_info_view.dart' show mostRecentPitEntryByTeam;

class TeamNotesLookupSection extends StatefulWidget {
  const TeamNotesLookupSection({
    required this.scoutingController,
    this.pitScoutingController,
    this.pitScoutConfigController,
    this.trexTraitReportController,
    this.assistant,
    this.eventKey = '',
    this.canPublishSummaries = false,
    super.key,
  });

  final ScoutingController scoutingController;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  final TrexTraitReportController? trexTraitReportController;

  final AssistantService? assistant;

  final String eventKey;

  final bool canPublishSummaries;

  @override
  State<TeamNotesLookupSection> createState() => _TeamNotesLookupSectionState();
}

class _TeamNotesLookupSectionState extends State<TeamNotesLookupSection> {
  final TextEditingController _teamNumber = TextEditingController();

  int? _committedTeam;

  @override
  void dispose() {
    _teamNumber.dispose();
    super.dispose();
  }

  void _commit() {
    setState(() {
      _committedTeam = int.tryParse(_teamNumber.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.scoutingController];
    final pit = widget.pitScoutingController;
    if (pit != null) listenables.add(pit);
    final trex = widget.trexTraitReportController;
    if (trex != null) listenables.add(trex);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final team = _committedTeam;
        final notes = team == null
            ? const <TeamLookupNote>[]
            : TeamLookupNotes.notesForTeam(
                teamNumber: team,
                scoutEntries: widget.scoutingController.entries,
                pitEntry: mostRecentPitEntryByTeam(pit?.entries)[team],
                pitConfig: widget.pitScoutConfigController?.config,
                trexReports: trex?.reports ?? const <TrexTraitReport>[],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Team lookup',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: TextField(
                controller: _teamNumber,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _commit(),
                decoration: InputDecoration(
                  labelText: 'Team number',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Look up',
                    onPressed: _commit,
                  ),
                ),
              ),
            ),
            if (team != null) ...[
              const SizedBox(height: 12),
              if (notes.isEmpty)
                Text(
                  'No notes recorded for team $team yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                for (final note in notes) _TeamNoteCard(note: note),
                _TeamLookupSummaryCard(
                  teamNumber: team,
                  eventKey: widget.eventKey,
                  notes: notes,
                  assistant: widget.assistant,
                  canPublish: widget.canPublishSummaries,
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _TeamNoteCard extends StatelessWidget {
  const _TeamNoteCard({required this.note});

  final TeamLookupNote note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.heading,
            style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(note.text, style: text.bodyMedium),
        ],
      ),
    );
  }
}

class _TeamLookupSummaryCard extends StatefulWidget {
  const _TeamLookupSummaryCard({
    required this.teamNumber,
    required this.eventKey,
    required this.notes,
    required this.assistant,
    required this.canPublish,
  });

  final int teamNumber;
  final String eventKey;
  final List<TeamLookupNote> notes;
  final AssistantService? assistant;
  final bool canPublish;

  @override
  State<_TeamLookupSummaryCard> createState() => _TeamLookupSummaryCardState();
}

class _TeamLookupSummaryCardState extends State<_TeamLookupSummaryCard> {
  AssistantSummary? _summary;
  bool _available = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_TeamLookupSummaryCard old) {
    super.didUpdateWidget(old);
    if (old.teamNumber != widget.teamNumber ||
        old.eventKey != widget.eventKey) {
      _summary = null;
      _error = null;
      _working = false;
      _load();
    }
  }

  Future<void> _load() async {
    final assistant = widget.assistant;
    final requestedTeam = widget.teamNumber;
    if (assistant == null || widget.eventKey.isEmpty) {
      return;
    }
    final available = await assistant.isAvailable();
    final cached = available
        ? await assistant.peek(
            AssistantRequest(
              cacheKey: TeamLookupSummary.cacheKeyFor(
                teamNumber: widget.teamNumber,
                eventKey: widget.eventKey,
              ),
              prompt: '',
            ),
          )
        : null;
    if (!mounted || widget.teamNumber != requestedTeam) {
      return;
    }
    setState(() {
      _available = available;
      _summary = cached;
    });

    if (cached == null && available && widget.canPublish) {
      await _generate(force: false);
    }
  }

  Future<void> _generate({required bool force}) async {
    final assistant = widget.assistant;
    final team = widget.teamNumber;
    final request = TeamLookupSummary.request(
      teamNumber: team,
      eventKey: widget.eventKey,
      notes: widget.notes,
    );
    if (assistant == null || request == null) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });

    bool current() => mounted && widget.teamNumber == team;
    try {
      final summary = await assistant.generate(request, force: force);
      if (current()) {
        setState(() => _summary = summary);
      }
    } on AssistantUnavailable catch (error) {
      if (current()) {
        setState(() => _error = error.reason);
      }
    } catch (error) {
      if (current()) {
        setState(() => _error = 'Could not save the summary: $error');
      }
    } finally {
      if (current()) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assistant == null ||
        widget.eventKey.isEmpty ||
        !_available ||
        widget.notes.length < TeamLookupSummary.minimumNotes) {
      return const SizedBox.shrink();
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Summary',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (summary != null && !_working && widget.canPublish)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Write it again',
                  onPressed: () => _generate(force: true),
                ),
            ],
          ),
          if (_working) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reading ${widget.notes.length} notes. This can take a '
                    'while on a free model.',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (summary == null) ...[
            const SizedBox(height: 4),
            Text(
              widget.canPublish
                  ? '${widget.notes.length} notes on this team. The summary '
                        'is not written until you ask for it.'
                  : '${widget.notes.length} notes on this team. No summary '
                        'yet. A strategy lead can write one.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (widget.canPublish) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Summarise the notes'),
                  onPressed: () => _generate(force: false),
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 8),
            Text(summary.text, style: text.bodyMedium),
            const SizedBox(height: 8),
            Text(
              _provenance(summary),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ],
      ),
    );
  }

  String _provenance(AssistantSummary summary) {
    final covered = summary.coverage;
    final parts = <String>[
      if (covered == null)
        'Written by ${summary.model}'
      else if (covered < widget.notes.length)
        'Written from $covered of ${widget.notes.length} notes by '
            '${summary.model}'
      else
        'Written from $covered notes by ${summary.model}',
      _ago(summary.generatedAt),
    ];
    return '${parts.join(', ')}. Check it against the notes above.';
  }

  static String _ago(DateTime at) {
    final elapsed = DateTime.now().toUtc().difference(at.toUtc());
    if (elapsed.inMinutes < 1) {
      return 'just now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} minutes ago';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours} hours ago';
    }
    return '${elapsed.inDays} days ago';
  }
}
