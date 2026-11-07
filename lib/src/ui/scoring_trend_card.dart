import 'package:flutter/material.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../models/cycle_log.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/scoring_trend_analysis.dart';
import '../services/statbotics/team_history_service.dart';
import '../theme/strategy_palette.dart';

class ScoringTrendCard extends StatefulWidget {
  const ScoringTrendCard({
    this.canPublish = true,
    required this.assistant,
    required this.teamNumber,
    required this.eventKey,
    required this.series,
    this.history,
    this.cycleLogs = const <CycleLog>[],
    super.key,
  });

  final AssistantService? assistant;
  final int teamNumber;
  final String eventKey;
  final List<MatchScorePoint> series;

  final TeamHistoryService? history;

  final List<CycleLog> cycleLogs;

  final bool canPublish;

  @override
  State<ScoringTrendCard> createState() => _ScoringTrendCardState();
}

class _ScoringTrendCardState extends State<ScoringTrendCard> {
  AssistantSummary? _summary;
  List<StatboticsTeamYear> _seasons = const <StatboticsTeamYear>[];
  bool _available = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ScoringTrendCard old) {
    super.didUpdateWidget(old);
    if (old.teamNumber != widget.teamNumber ||
        old.eventKey != widget.eventKey) {
      _summary = null;
      _seasons = const <StatboticsTeamYear>[];
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    final assistant = widget.assistant;
    final seasons =
        await widget.history?.seasonsFor(widget.teamNumber) ??
        const <StatboticsTeamYear>[];
    if (assistant == null) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _seasons = seasons;
      });
      return;
    }
    final available = await assistant.isAvailable();
    final cycles = ScoringTrendAnalysis.cycleSummary(widget.cycleLogs);
    final cached = available
        ? await assistant.peek(
            AssistantRequest(
              cacheKey: ScoringTrendAnalysis.cacheKeyFor(
                teamNumber: widget.teamNumber,
                eventKey: widget.eventKey,
                seasons: seasons,
                cycles: cycles,
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
      _seasons = seasons;
      _summary = cached;
    });

    if (cached == null && available && widget.canPublish) {
      await _generate(force: false);
    }
  }

  Future<void> _generate({required bool force}) async {
    final assistant = widget.assistant;
    final request = ScoringTrendAnalysis.request(
      teamNumber: widget.teamNumber,
      eventKey: widget.eventKey,
      series: widget.series,
      seasons: _seasons,
      cycleLogs: widget.cycleLogs,
      totalMatches: widget.series.length,
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
    final hasChart =
        widget.series.length >= ScoringTrendAnalysis.minimumMatches;
    final cycles = ScoringTrendAnalysis.cycleSummary(widget.cycleLogs);

    final hasAi = widget.assistant != null && _available && hasChart;

    if (!hasChart && _seasons.isEmpty && cycles == null) {
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
                    'Scoring trend',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasAi && summary != null && !_working && widget.canPublish)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Write it again',
                    onPressed: () => _generate(force: true),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (hasChart) ...[
              _ScoreTrendChart(series: widget.series),
              const SizedBox(height: 4),
              Text(
                'Total score per match at this event, in scouting points.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],
            if (hasAi) ...[
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
                        'Reading ${widget.series.length} matches. This can '
                        'take a while on a free model.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (summary == null) ...[
                Text(
                  widget.canPublish
                      ? '${widget.series.length} matches at this event. The '
                            'explanation is not written until you ask for it.'
                      : '${widget.series.length} matches at this event. No '
                            'explanation yet. A strategy lead can write one.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (widget.canPublish) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Explain the trend'),
                      onPressed: () => _generate(force: false),
                    ),
                  ),
                ],
              ] else ...[
                Text(summary.text, style: text.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  _provenance(summary),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (_seasons.isEmpty)
              Text(
                'No season history for this team.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              _SeasonHistory(seasons: _seasons),
            if (cycles != null) ...[
              const SizedBox(height: 12),
              _CycleTrendSection(
                summary: cycles,
                totalMatches: widget.series.length > cycles.matchesCovered
                    ? widget.series.length
                    : cycles.matchesCovered,
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
      else if (covered < widget.series.length)
        'Written from $covered of ${widget.series.length} matches by '
            '${summary.model}'
      else
        'Written from $covered matches by ${summary.model}',
      _ago(summary.generatedAt),
    ];
    return '${parts.join(', ')}. Check it against the chart above.';
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

class _SeasonHistory extends StatelessWidget {
  const _SeasonHistory({required this.seasons});

  final List<StatboticsTeamYear> seasons;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent seasons',
          style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final season in seasons) ...[
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${season.year}  ',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: _measures(season),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          'EPA is Statbotics. Points differ by game, so seasons compare on '
          'the normalized scale and world rank, not on points.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static String _measures(StatboticsTeamYear season) {
    final parts = <String>[];
    final norm = season.epa.norm;
    if (norm != null) {
      parts.add('normalized EPA ${_num(norm)}');
    }
    final rank = season.epaRank;
    if (rank != null) {
      final count = season.epaRankTeamCount;
      parts.add(count == null ? 'rank $rank' : 'rank $rank of $count');
    }
    parts.add('${season.wins}-${season.losses}-${season.ties}');
    final total = season.epa.totalPoints;
    if (total != null) {
      parts.add('${_num(total)} EPA points that season');
    }
    return parts.join(', ');
  }

  static String _num(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _CycleTrendSection extends StatelessWidget {
  const _CycleTrendSection({required this.summary, required this.totalMatches});

  final CycleTimeSummary summary;
  final int totalMatches;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cycle time (filmed matches)',
          style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${summary.meanLabel} avg  ',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text:
                    '${summary.medianLabel} median, ${summary.cycleCount} '
                    'cycles',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'From ${summary.matchesCovered} of $totalMatches matches at this '
          'event -- only the ones someone filmed with the cycle logger.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ScoreTrendChart extends StatelessWidget {
  const _ScoreTrendChart({required this.series});

  final List<MatchScorePoint> series;

  static const double _barWidth = 14;
  static const double _gap = 6;
  static const double _chartHeight = 96;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = StrategyPalette.surfaceStrongOf(context);
    final maxScore = series
        .map((point) => point.totalScore)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Peak ${_fmt(maxScore)} pts',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: _chartHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in series) ...[
                  Tooltip(
                    message:
                        '${point.matchLabel}: ${_fmt(point.totalScore)} pts',
                    child: Container(
                      width: _barWidth,
                      height: _chartHeight,
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        widthFactor: 1,
                        heightFactor: maxScore == 0
                            ? 0
                            : (point.totalScore / maxScore).clamp(0.02, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(StrategyPalette.radiusSm),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: _gap),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 2, color: track),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                series.first.matchLabel,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                series.last.matchLabel,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmt(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}
