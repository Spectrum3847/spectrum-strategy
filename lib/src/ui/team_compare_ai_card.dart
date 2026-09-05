import 'package:flutter/material.dart';

import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/models/team_analysis.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/team_compare_summary.dart';
import '../theme/strategy_palette.dart';

class TeamCompareAiCard extends StatefulWidget {
  const TeamCompareAiCard({
    required this.assistant,
    required this.teamNumber,
    required this.eventKey,
    required this.entries,
    required this.notes,
    this.config,
    super.key,
  });

  final AssistantService? assistant;
  final int teamNumber;
  final String eventKey;

  final List<ScoutEntry> entries;

  final List<TeamNote> notes;
  final ScoutConfig? config;

  @override
  State<TeamCompareAiCard> createState() => _TeamCompareAiCardState();
}

class _TeamCompareAiCardState extends State<TeamCompareAiCard> {
  AssistantSummary? _summary;
  bool _available = false;
  bool _working = false;
  String? _error;
  bool _showAllComments = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TeamCompareAiCard old) {
    super.didUpdateWidget(old);
    if (old.teamNumber != widget.teamNumber ||
        old.eventKey != widget.eventKey) {
      _summary = null;
      _error = null;
      _showAllComments = false;
      _load();
    }
  }

  Future<void> _load() async {
    final assistant = widget.assistant;
    if (assistant == null) return;
    final available = await assistant.isAvailable();
    final cached = available
        ? await assistant.peek(
            AssistantRequest(
              cacheKey: TeamCompareSummary.cacheKeyFor(
                teamNumber: widget.teamNumber,
                eventKey: widget.eventKey,
              ),
              prompt: '',
            ),
          )
        : null;
    if (!mounted) return;
    setState(() {
      _available = available;
      _summary = cached;
    });
  }

  Future<void> _generate({required bool force}) async {
    final assistant = widget.assistant;
    final request = TeamCompareSummary.request(
      teamNumber: widget.teamNumber,
      eventKey: widget.eventKey,
      entries: widget.entries,
      notes: widget.notes,
      config: widget.config,
    );
    if (assistant == null || request == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final summary = await assistant.generate(request, force: force);
      if (mounted) setState(() => _summary = summary);
    } on AssistantUnavailable catch (error) {
      if (mounted) setState(() => _error = error.reason);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the summary: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool get _hasData =>
      widget.entries.any((e) => e.teamNumber == widget.teamNumber);

  @override
  Widget build(BuildContext context) {
    if (widget.assistant == null || !_available || !_hasData) {
      return const SizedBox.shrink();
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'AI summary',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (summary != null && !_working)
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
                      'Reading team ${widget.teamNumber}\'s data. This can '
                      'take a while on a free model.',
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
                'The summary is not written until you ask for it.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate summary'),
                  onPressed: () => _generate(force: false),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(summary.text, style: text.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'Written by ${summary.model}, ${_ago(summary.generatedAt)}.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (widget.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _showAllComments = !_showAllComments),
                  child: Text(
                    _showAllComments
                        ? 'Hide scouter comments'
                        : 'Show All Scouter Comments (${widget.notes.length})',
                  ),
                ),
              ),
              if (_showAllComments)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StrategyPalette.surfaceOf(context),
                    borderRadius: BorderRadius.circular(
                      StrategyPalette.radiusSm,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in widget.notes) ...[
                        Text(note.text, style: text.bodySmall),
                        Text(
                          _noteContext(note),
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _noteContext(TeamNote note) {
    final parts = <String>[
      if (note.matchId.isNotEmpty) note.matchId,
      if (note.phase != null) note.phase!.label,
      if (note.author.isNotEmpty) note.author,
    ];
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  static String _ago(DateTime at) {
    final elapsed = DateTime.now().toUtc().difference(at.toUtc());
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} minutes ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours} hours ago';
    return '${elapsed.inDays} days ago';
  }
}
