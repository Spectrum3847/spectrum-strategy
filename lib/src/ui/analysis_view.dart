import 'package:flutter/material.dart';

import '../models/cycle_log.dart';
import '../scouting/models/team_analysis.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../scouting/widgets/scout_drawing_canvas.dart';
import '../theme/strategy_palette.dart';

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class TeamCommentList extends StatelessWidget {
  const TeamCommentList({required this.notes, super.key});

  final List<TeamNote> notes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in notes)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.text, style: text.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    _noteContext(note),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _noteContext(TeamNote note) {
    final parts = <String>[];
    if (note.matchId.isNotEmpty) parts.add('Match ${note.matchId}');
    if (note.phase != null) parts.add(note.phase!.label);
    if (note.author.isNotEmpty) parts.add(note.author);
    return parts.join(' · ');
  }
}

class ReportGroupSection extends StatelessWidget {
  const ReportGroupSection({required this.group, super.key});

  final TeamReportGroup group;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            group.groupName,
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        for (final report in _reportsWithDrawingShownOnce())
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.report.text, style: text.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    _reportContext(report.report),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (report.showDrawing) ...[
                    const SizedBox(height: 8),
                    _ReportDrawingThumbnail(report: report.report),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  List<_ReportWithDrawing> _reportsWithDrawingShownOnce() {
    final seenEntries = <String>{};
    return <_ReportWithDrawing>[
      for (final report in group.reports)
        _ReportWithDrawing(
          report: report,
          showDrawing: report.hasDrawing && seenEntries.add(report.entryId),
        ),
    ];
  }

  String _reportContext(TeamReport report) {
    final parts = <String>[report.fieldTitle];
    if (report.matchId.isNotEmpty) parts.add('Match ${report.matchId}');
    if (report.author.isNotEmpty) parts.add(report.author);
    return parts.join(' · ');
  }
}

class _ReportWithDrawing {
  const _ReportWithDrawing({required this.report, required this.showDrawing});

  final TeamReport report;
  final bool showDrawing;
}

class _ReportDrawingThumbnail extends StatelessWidget {
  const _ReportDrawingThumbnail({required this.report});

  final TeamReport report;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open the drawing for this report',
      child: InkWell(
        onTap: () => _open(context),
        child: SizedBox(
          height: 96,
          child: IgnorePointer(
            child: ReadOnlyDrawingPreview(
              strokesByPhase: report.strokesByPhase,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.matchId.isEmpty
                          ? report.fieldTitle
                          : '${report.fieldTitle} · Match ${report.matchId}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ReadOnlyDrawingPreview(strokesByPhase: report.strokesByPhase),
            ],
          ),
        ),
      ),
    );
  }
}

class PhaseScoreBars extends StatelessWidget {
  const PhaseScoreBars({required this.analysis, super.key});

  final TeamAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final scale = StrategyPhase.values
        .map((p) => analysis.phaseStats(p).iqmScore)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        for (final phase in StrategyPhase.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PhaseBar(
              label: phase.label,
              value: analysis.phaseStats(phase).iqmScore,
              fraction: scale == 0
                  ? 0
                  : analysis.phaseStats(phase).iqmScore / scale,
              fill: Theme.of(context).colorScheme.primary,
            ),
          ),
      ],
    );
  }
}

class PhaseDetail extends StatelessWidget {
  const PhaseDetail({required this.phase, required this.stats, super.key});

  final StrategyPhase phase;
  final PhaseStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final counters = stats.avgCounters.entries
        .where((e) => stats.totalCounters[e.key] != null)
        .toList();
    counters.sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                phase.label,
                style: text.labelLarge?.copyWith(color: scheme.onSurface),
              ),
              const Spacer(),
              Text(
                '${formatStat(stats.iqmScore)} pts',
                style: text.bodyMedium?.copyWith(color: scheme.onSurface),
              ),
              if (stats.avgPenalties > 0) ...[
                const SizedBox(width: 12),
                Text(
                  '${formatStat(stats.avgPenalties)} pen',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (counters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                counters
                    .map((e) => '${e.key} ${formatStat(e.value)}')
                    .join('  ·  '),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          const _RowDivider(),
        ],
      ),
    );
  }
}

class CycleTimesSection extends StatelessWidget {
  const CycleTimesSection({required this.logs, super.key});

  final List<CycleLog> logs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final cycles = <int>[for (final log in logs) ...log.cycleTimesMs]..sort();
    final mean = cycles.isEmpty
        ? null
        : cycles.reduce((a, b) => a + b) / cycles.length;
    final median = cycles.isEmpty
        ? null
        : cycles.length.isOdd
        ? cycles[cycles.length ~/ 2].toDouble()
        : (cycles[cycles.length ~/ 2 - 1] + cycles[cycles.length ~/ 2]) / 2;

    int countOf(CycleEventKind kind) =>
        logs.fold(0, (sum, log) => sum + log.countOf(kind));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              mean == null ? '--' : _seconds(mean),
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'avg cycle',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (median != null)
              _MetaChip(
                icon: Icons.timeline_rounded,
                label: '${_seconds(median)} median',
              ),
            _MetaChip(
              icon: Icons.loop_rounded,
              label: cycles.length == 1 ? '1 cycle' : '${cycles.length} cycles',
            ),
            _MetaChip(
              icon: Icons.download_rounded,
              label: '${countOf(CycleEventKind.intake)} intake',
            ),
            _MetaChip(
              icon: Icons.sports_score_rounded,
              label: '${countOf(CycleEventKind.score)} score',
            ),
            if (countOf(CycleEventKind.feed) > 0)
              _MetaChip(
                icon: Icons.volunteer_activism_rounded,
                label: '${countOf(CycleEventKind.feed)} feed',
              ),
            if (countOf(CycleEventKind.defense) > 0)
              _MetaChip(
                icon: Icons.shield_outlined,
                label: '${countOf(CycleEventKind.defense)} defense',
              ),
          ],
        ),
      ],
    );
  }

  String _seconds(double ms) => '${(ms / 1000).toStringAsFixed(1)}s';
}

class CompareTeamsScreen extends StatelessWidget {
  const CompareTeamsScreen({
    required this.controller,
    required this.configController,
    required this.teamA,
    required this.teamB,
    super.key,
  });

  final ScoutingController controller;
  final ScoutConfigController configController;
  final int teamA;
  final int teamB;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, configController]),
      builder: (context, _) {
        final entries = controller.entries;
        final config = configController.config;
        final a = ScoutingAnalysis.analyzeTeam(teamA, entries, config: config);
        final b = ScoutingAnalysis.analyzeTeam(teamB, entries, config: config);
        final scheme = Theme.of(context).colorScheme;

        final scale = StrategyPhase.values
            .expand((p) => [a.phaseStats(p).iqmScore, b.phaseStats(p).iqmScore])
            .fold<double>(0, (x, y) => x > y ? x : y);

        return Scaffold(
          appBar: AppBar(titleSpacing: 0, title: const Text('Compare teams')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _CompareHeader(a: a, b: b),
                  const SizedBox(height: 24),
                  _SectionLabel('IQM score by phase'),
                  const SizedBox(height: 12),
                  for (final phase in StrategyPhase.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phase.label,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: scheme.onSurface),
                          ),
                          const SizedBox(height: 8),
                          PhaseBar(
                            label: 'Team ${a.teamNumber}',
                            value: a.phaseStats(phase).iqmScore,
                            fraction: scale == 0
                                ? 0
                                : a.phaseStats(phase).iqmScore / scale,
                            fill: scheme.primary,
                          ),
                          const SizedBox(height: 6),
                          PhaseBar(
                            label: 'Team ${b.teamNumber}',
                            value: b.phaseStats(phase).iqmScore,
                            fraction: scale == 0
                                ? 0
                                : b.phaseStats(phase).iqmScore / scale,
                            fill: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompareHeader extends StatelessWidget {
  const _CompareHeader({required this.a, required this.b});

  final TeamAnalysis a;
  final TeamAnalysis b;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _CompareTotal(
            analysis: a,
            color: scheme.primary,
            align: CrossAxisAlignment.start,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'vs',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: _CompareTotal(
            analysis: b,
            color: scheme.onSurfaceVariant,
            align: CrossAxisAlignment.end,
          ),
        ),
      ],
    );
  }
}

class _CompareTotal extends StatelessWidget {
  const _CompareTotal({
    required this.analysis,
    required this.color,
    required this.align,
  });

  final TeamAnalysis analysis;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          'Team ${analysis.teamNumber}',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatStat(analysis.iqmTotalScore),
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        Text(
          analysis.entryCount == 1
              ? '1 entry'
              : '${analysis.entryCount} entries',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class PhaseBar extends StatelessWidget {
  const PhaseBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.fill,
    super.key,
  });

  final String label;
  final double value;
  final double fraction;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final track = StrategyPalette.surfaceStrongOf(context);

    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
            child: Container(
              height: 12,
              color: track,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(color: fill),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            formatStat(value),
            textAlign: TextAlign.end,
            style: text.bodyMedium?.copyWith(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceStrongOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

Future<int?> pickOpponentTeam(
  BuildContext context, {
  required ScoutingController controller,
  required ScoutConfigController configController,
  required int excludeTeam,
}) {
  return _pickRankedTeam(
    context,
    controller: controller,
    configController: configController,
    title: 'Compare Team $excludeTeam with',
    isExcluded: (teamNumber) => teamNumber == excludeTeam,
  );
}

Future<int?> _pickRankedTeam(
  BuildContext context, {
  required ScoutingController controller,
  required ScoutConfigController configController,
  required String title,
  required bool Function(int teamNumber) isExcluded,
}) {
  final teams = ScoutingAnalysis.rankByScore(
    controller.entries,
    config: configController.config,
  ).where((a) => !isExcluded(a.teamNumber)).toList();

  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in teams)
                    ListTile(
                      title: Text('Team ${a.teamNumber}'),
                      trailing: Text(
                        '${formatStat(a.iqmTotalScore)} IQM',
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(a.teamNumber),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

String formatStat(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String formatDate(DateTime utc) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = utc.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}
