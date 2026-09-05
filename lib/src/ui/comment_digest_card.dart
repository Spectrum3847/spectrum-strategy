import 'package:flutter/material.dart';

import '../scouting/models/team_analysis.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/comment_digest.dart';

class CommentDigestCard extends StatefulWidget {
  const CommentDigestCard({
    this.canPublish = true,
    required this.assistant,
    required this.teamNumber,
    required this.eventKey,
    required this.notes,
    super.key,
  });

  final AssistantService? assistant;
  final int teamNumber;
  final String eventKey;
  final List<TeamNote> notes;

  final bool canPublish;

  @override
  State<CommentDigestCard> createState() => _CommentDigestCardState();
}

class _CommentDigestCardState extends State<CommentDigestCard> {
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
  void didUpdateWidget(CommentDigestCard old) {
    super.didUpdateWidget(old);
    if (old.teamNumber != widget.teamNumber ||
        old.eventKey != widget.eventKey) {
      _summary = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    final assistant = widget.assistant;
    if (assistant == null) {
      return;
    }
    final available = await assistant.isAvailable();
    final cached = available
        ? await assistant.peek(
            AssistantRequest(
              cacheKey: CommentDigest.cacheKeyFor(
                teamNumber: widget.teamNumber,
                eventKey: widget.eventKey,
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
      _summary = cached;
    });

    if (cached == null && available && widget.canPublish) {
      await _generate(force: false);
    }
  }

  Future<void> _generate({required bool force}) async {
    final assistant = widget.assistant;
    final request = CommentDigest.request(
      teamNumber: widget.teamNumber,
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
        setState(() => _error = 'Could not save the summary: $error');
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
        !_available ||
        widget.notes.length < CommentDigest.minimumNotes) {
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
                    'What the scouters keep saying',
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
                      'Reading ${widget.notes.length} comments. This can take '
                      'a while on a free model.',
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
                    ? '${widget.notes.length} comments on this team. The '
                          'summary is not written until you ask for it.'
                    : '${widget.notes.length} comments on this team. No '
                          'summary yet. A strategy lead can write one.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (widget.canPublish) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Summarise the comments'),
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

  String _provenance(AssistantSummary summary) {
    final covered = summary.coverage;
    final parts = <String>[
      if (covered == null)
        'Written by ${summary.model}'
      else if (covered < widget.notes.length)
        'Written from $covered of ${widget.notes.length} comments by '
            '${summary.model}'
      else
        'Written from $covered comments by ${summary.model}',
      _ago(summary.generatedAt),
    ];
    return '${parts.join(', ')}. Check it against the comments below.';
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
