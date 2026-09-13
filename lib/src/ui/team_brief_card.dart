import 'package:flutter/material.dart';

import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/team_brief.dart';
import '../services/statbotics/team_history_service.dart';

class TeamBriefCard extends StatefulWidget {
  const TeamBriefCard({
    this.canPublish = true,
    required this.assistant,
    required this.teamNumber,
    this.history,
    super.key,
  });

  final AssistantService? assistant;
  final int teamNumber;

  final TeamHistoryService? history;

  final bool canPublish;

  @override
  State<TeamBriefCard> createState() => _TeamBriefCardState();
}

class _TeamBriefCardState extends State<TeamBriefCard> {
  AssistantSummary? _summary;
  TeamBriefInputs _inputs = const TeamBriefInputs();
  bool _available = false;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TeamBriefCard old) {
    super.didUpdateWidget(old);
    if (old.teamNumber != widget.teamNumber) {
      _summary = null;
      _inputs = const TeamBriefInputs();
      _error = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final assistant = widget.assistant;
    final history = widget.history;
    if (assistant == null || history == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final available = await assistant.isAvailable();
    final inputs = await history.briefInputsFor(widget.teamNumber);
    final cached = available
        ? await assistant.peek(
            AssistantRequest(
              cacheKey: TeamBrief.cacheKeyFor(
                teamNumber: widget.teamNumber,
                inputs: inputs,
              ),
              prompt: '',
            ),
          )
        : null;
    if (!mounted) {
      return;
    }
    setState(() {
      _available = available;
      _inputs = inputs;
      _summary = cached;
      _loading = false;
    });

    if (cached == null && available && widget.canPublish) {
      await _generate(force: false);
    }
  }

  Future<void> _generate({required bool force}) async {
    final assistant = widget.assistant;
    final request = TeamBrief.request(
      teamNumber: widget.teamNumber,
      inputs: _inputs,
    );
    if (assistant == null || request == null) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final summary = await assistant.generate(request, force: force);
      if (mounted) {
        setState(() => _summary = summary);
      }
    } on AssistantUnavailable catch (error) {
      if (mounted) {
        setState(() => _error = error.reason);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the brief: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assistant == null ||
        widget.history == null ||
        _loading ||
        !_available ||
        _inputs.events.length < TeamBrief.minimumEvents) {
      return const SizedBox.shrink();
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Brief from previous events',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
            const SizedBox(height: 4),
            Text(
              _coverage(),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (_working) ...[
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
                      'Reading ${_inputs.events.length} events. This can '
                      'take a while on a free model.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (summary == null) ...[
              if (widget.canPublish)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Write the brief'),
                    onPressed: () => _generate(force: false),
                  ),
                )
              else
                Text(
                  'No brief written yet. A strategy lead can write one.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ] else ...[
              Text(summary.text, style: text.bodyMedium),
              const SizedBox(height: 8),
              Text(
                _provenance(summary),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),

              Text(
                'Written by a model from public results. Check any warning '
                'against the event it names before repeating it.',
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
          ],
        ),
      ),
    );
  }

  String _coverage() {
    final events = _inputs.events.length;

    final years = _inputs.years.reversed.toList();
    final span = years.isEmpty
        ? ''
        : years.length == 1
        ? ' in ${years.single}'
        : ' in ${years.take(years.length - 1).join(', ')} and ${years.last}';
    final awards = _inputs.awards.length;
    final awardPart = awards == 0
        ? 'no awards'
        : awards == 1
        ? '1 award'
        : '$awards awards';
    return '$events events$span, $awardPart.';
  }

  String _provenance(AssistantSummary summary) {
    final covered = summary.coverage;
    final events = _inputs.events.length;
    final parts = <String>[
      if (covered == null)
        'Written by ${summary.model}'
      else if (covered < events)
        'Written from $covered of $events events by ${summary.model}'
      else
        'Written from $covered events by ${summary.model}',
      _ago(summary.generatedAt),
    ];
    return '${parts.join(', ')}.';
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
