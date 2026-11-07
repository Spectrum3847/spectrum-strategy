import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../models/post_match_report.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/post_match_analysis.dart';

class PostMatchAnalysisCard extends StatefulWidget {
  const PostMatchAnalysisCard({
    required this.assistant,
    required this.eventKey,
    required this.matchId,
    required this.report,
    this.tbaMatch,
    this.myTeamNumber,
    super.key,
  });

  final AssistantService? assistant;
  final String eventKey;
  final String matchId;
  final PostMatchReport report;
  final TbaScheduleMatch? tbaMatch;
  final int? myTeamNumber;

  @override
  State<PostMatchAnalysisCard> createState() => _PostMatchAnalysisCardState();
}

class _PostMatchAnalysisCardState extends State<PostMatchAnalysisCard> {
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
  void didUpdateWidget(PostMatchAnalysisCard old) {
    super.didUpdateWidget(old);
    if (old.eventKey != widget.eventKey || old.matchId != widget.matchId) {
      _summary = null;
      _error = null;
      _load();
    }
  }

  AssistantRequest? get _request => PostMatchAnalysis.request(
    eventKey: widget.eventKey,
    matchId: widget.matchId,
    report: widget.report,
    tbaMatch: widget.tbaMatch,
    myTeamNumber: widget.myTeamNumber,
  );

  Future<void> _load() async {
    final assistant = widget.assistant;
    if (assistant == null) {
      return;
    }
    final available = await assistant.isAvailable();
    final cached = available
        ? await assistant.peek(
            AssistantRequest(
              cacheKey: PostMatchAnalysis.cacheKeyFor(
                eventKey: widget.eventKey,
                matchId: widget.matchId,
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
  }

  Future<void> _generate({required bool force}) async {
    final assistant = widget.assistant;
    final request = _request;
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
    if (widget.assistant == null || !_available) {
      return const SizedBox.shrink();
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    final request = _request;

    if (request == null && summary == null) {
      return const SizedBox.shrink();
    }

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
                    'AI summary',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (summary != null && !_working && request != null)
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
                      'Reading the report. This can take a while on a free '
                      'model.',
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
                  label: const Text('Summarise this report'),
                  onPressed: () => _generate(force: false),
                ),
              ),
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

  String _provenance(AssistantSummary summary) =>
      'Written by ${summary.model}, ${_ago(summary.generatedAt)}. Check it '
      'against the report above.';

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
