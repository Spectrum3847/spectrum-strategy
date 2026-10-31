import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../scouting/services/scouter_opr.dart';
import '../scouting/state/scouting_controller.dart';
import '../theme/strategy_palette.dart';

typedef FetchOfficialMatches = Future<List<TbaScheduleMatch>> Function(
  String eventKey,
);

String formatScoutMiss(double miss) {
  final rounded = (miss * 10).round() / 10;
  if (rounded == 0) return '0.0';
  return '${rounded > 0 ? '+' : '-'}${rounded.abs().toStringAsFixed(1)}';
}

String _bandLabel(ScouterBand band) => switch (band) {
  ScouterBand.ok => 'OK',
  ScouterBand.checkIn => 'Check in',
  ScouterBand.coach => 'Coach',
};

class ScoutAccuracyScreen extends StatefulWidget {
  const ScoutAccuracyScreen({
    required this.scoutingController,
    required this.eventKey,
    required this.fetchMatches,
    super.key,
  });

  final ScoutingController scoutingController;
  final String eventKey;
  final FetchOfficialMatches fetchMatches;

  @override
  State<ScoutAccuracyScreen> createState() => _ScoutAccuracyScreenState();
}

class _ScoutAccuracyScreenState extends State<ScoutAccuracyScreen> {
  List<OfficialAllianceFuel>? _official;
  Object? _error;
  bool _loading = false;

  int _memoRevision = -1;
  List<OfficialAllianceFuel>? _memoOfficial;
  ScouterOprReport _report = const ScouterOprReport.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.eventKey.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await widget.fetchMatches(widget.eventKey);
      if (!mounted) return;
      setState(() => _official = ScouterOpr.officialFuel(matches));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ScouterOprReport _reportFor(List<OfficialAllianceFuel> official) {
    final revision = widget.scoutingController.entriesRevision;
    if (revision != _memoRevision || !identical(official, _memoOfficial)) {
      _report = ScouterOpr.build(
        entries: widget.scoutingController.entries,
        official: official,
        eventKey: widget.eventKey,
      );
      _memoRevision = revision;
      _memoOfficial = official;
    }
    return _report;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scout accuracy'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh official counts',
            onPressed: _loading || widget.eventKey.isEmpty ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.scoutingController,
        builder: (BuildContext context, Widget? child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  static String _errorText(Object error) {
    if (error is TbaApiKeyMissingException) return '$error';
    if (error is TbaApiException && error.statusCode == 401) {
      return 'The Blue Alliance rejected the team TBA key. Ask an admin to '
          'replace it in the shared app config.';
    }
    return 'The Blue Alliance could not be reached. Check the connection '
        'and try Refresh.';
  }

  Widget _body(BuildContext context) {
    if (widget.eventKey.isEmpty) {
      return const _Notice('Load an event to see scout accuracy.');
    }
    final official = _official;
    if (official == null || official.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      final error = _error;
      if (error != null) return _Notice(_errorText(error));
      return const _Notice(
        'No played matches with fuel counts yet. The Blue Alliance posts '
        'them after each match.',
      );
    }
    final report = _reportFor(official);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (_loading) const LinearProgressIndicator(),
        Text(
          'For coaching, not blame. Each number is the fuel a scout misses '
          'per robot per match, worked out from how scouted alliance totals '
          'compare with the official count. Plus means under-counting, minus '
          'means over-counting. Within 4 is OK, within 12 is worth a check-in, '
          'more than 12 is worth coaching. It gets steadier as the event goes '
          'on.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _Coverage(report: report, refreshError: _error),
        const SizedBox(height: 12),
        if (report.equations == 0)
          Text(
            'No complete alliances yet. An alliance counts once each of its '
            'three robots in a played match has one scout entry with a scout '
            'name and a fuel count.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          for (final score in report.scouts) _ScoutRow(score: score),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _Coverage extends StatelessWidget {
  const _Coverage({required this.report, required this.refreshError});

  final ScouterOprReport report;
  final Object? refreshError;

  @override
  Widget build(BuildContext context) {
    final capture = report.averageCapture;
    String alliances(int n) => n == 1 ? '1 alliance' : '$n alliances';
    final lines = <String>[
      '${alliances(report.equations)} used',
      if (capture != null)
        'Scouts record ${(capture * 100).round()}% of official fuel on average',
      if (report.incomplete > 0)
        '${alliances(report.incomplete)} left out: a robot was not scouted',
      if (report.skipped > 0)
        '${alliances(report.skipped)} left out: a robot has two entries, or '
            'an entry has no scout name or fuel count',
      if (refreshError != null)
        'Refresh failed, so the official counts may be out of date',
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final line in lines)
              Text(line, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ScoutRow extends StatelessWidget {
  const _ScoutRow({required this.score});

  final ScouterScore score;

  Color _bandTint(BuildContext context) => switch (score.band) {
    ScouterBand.ok => StrategyPalette.surfaceStrongOf(context),
    ScouterBand.checkIn => StrategyPalette.flagNoticeOf(context),
    ScouterBand.coach => StrategyPalette.flagWarnOf(context),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enough = score.hasEnoughData;
    final muted = StrategyPalette.mutedTextOf(context);
    final ink = enough ? theme.colorScheme.onSurface : muted;
    final robots = score.robots == 1
        ? '1 robot scouted'
        : '${score.robots} robots scouted';
    final miss = formatScoutMiss(score.miss);
    return Semantics(
      label: enough
          ? '${score.name}, $miss fuel per robot per match, '
                '${_bandLabel(score.band)}, $robots'
          : '${score.name}, $miss fuel per robot per match, '
                '$robots, not enough data yet',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: StrategyPalette.borderOf(context)),
          borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    score.name,
                    style: theme.textTheme.titleSmall?.copyWith(color: ink),
                  ),
                  Text(
                    robots,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (!enough)
                    Text(
                      'Not enough data yet',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  miss,
                  style: theme.textTheme.titleMedium?.copyWith(color: ink),
                ),
                if (enough)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _bandTint(context),
                      borderRadius: BorderRadius.circular(
                        StrategyPalette.radiusSm,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        _bandLabel(score.band),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
