import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cycle_log.dart';
import '../models/strategy_session.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_service.dart';
import '../services/match_directory.dart';
import '../state/cycle_log_controller.dart';
import '../state/failed_write_tracker.dart';
import '../state/post_match_report_controller.dart';
import '../state/user_role_controller.dart';

import 'package:tba_client/tba_client.dart';

import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/sync_status_pill.dart';
import 'post_match_report_screen.dart';

class FilmReviewScreen extends StatefulWidget {
  const FilmReviewScreen({
    required this.scoutingController,
    this.tbaClient,
    this.matchDirectory,
    this.cycleLogController,
    this.embedded = false,
    this.eventKey = '',
    this.postMatchReportController,
    this.userRoleController,
    this.myTeamNumber,
    this.assistant,
    super.key,
  });

  final ScoutingController scoutingController;
  final TbaClient? tbaClient;
  final MatchDirectory? matchDirectory;
  final CycleLogController? cycleLogController;

  final bool embedded;

  final String eventKey;

  final PostMatchReportController? postMatchReportController;

  final UserRoleController? userRoleController;

  final int? myTeamNumber;

  final AssistantService? assistant;

  @override
  State<FilmReviewScreen> createState() => _FilmReviewScreenState();
}

class _FilmReviewScreenState extends State<FilmReviewScreen> {
  String? _selectedMatchId;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: widget.scoutingController,
      builder: (context, _) {
        final entries = widget.scoutingController.entries;
        final matchIds = _distinctMatchIds(entries);

        if (matchIds.isEmpty) {
          return const EmptyState(
            icon: Icons.movie_creation_outlined,
            message:
                'No scouting entries yet.\n'
                'Scout some matches first, then come back to review them with video.',
          );
        }

        if (_selectedMatchId != null && !matchIds.contains(_selectedMatchId)) {
          _selectedMatchId = null;
        }

        if (_selectedMatchId == null) {
          return _MatchPicker(
            matchIds: matchIds,
            entries: entries,
            onSelect: (id) => setState(() => _selectedMatchId = id),
          );
        }

        final matchEntries =
            entries.where((e) => e.matchId == _selectedMatchId).toList()
              ..sort((a, b) => a.teamNumber.compareTo(b.teamNumber));

        return _MatchReview(
          matchId: _selectedMatchId!,
          entries: matchEntries,
          tbaClient: widget.tbaClient,
          matchDirectory: widget.matchDirectory,
          cycleLogController: widget.cycleLogController,
          eventKey: widget.eventKey,
          postMatchReportController: widget.postMatchReportController,
          userRoleController: widget.userRoleController,
          myTeamNumber: widget.myTeamNumber,
          assistant: widget.assistant,
          onBack: () => setState(() => _selectedMatchId = null),
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Film review')),
      body: body,
    );
  }

  List<String> _distinctMatchIds(List<ScoutEntry> entries) {
    final seen = <String>{};
    for (final e in entries) {
      if (e.matchId.isNotEmpty) {
        seen.add(e.matchId);
      }
    }
    return seen.toList(growable: false)..sort();
  }
}

class _MatchPicker extends StatelessWidget {
  const _MatchPicker({
    required this.matchIds,
    required this.entries,
    required this.onSelect,
  });

  final List<String> matchIds;
  final List<ScoutEntry> entries;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: matchIds.length,
          itemBuilder: (context, index) {
            final matchId = matchIds[index];
            final count = entries.where((e) => e.matchId == matchId).length;
            final teams =
                entries
                    .where((e) => e.matchId == matchId)
                    .map((e) => e.teamNumber)
                    .toList()
                  ..sort();
            final teamsStr = teams.join(', ');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.movie_creation_outlined),
                title: Text('Match $matchId'),
                subtitle: Text(
                  '$count ${count == 1 ? 'entry' : 'entries'} · Teams: $teamsStr',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onSelect(matchId),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MatchReview extends StatefulWidget {
  const _MatchReview({
    required this.matchId,
    required this.entries,
    required this.onBack,
    this.tbaClient,
    this.matchDirectory,
    this.cycleLogController,
    this.eventKey = '',
    this.postMatchReportController,
    this.userRoleController,
    this.myTeamNumber,
    this.assistant,
  });

  final String matchId;
  final List<ScoutEntry> entries;
  final VoidCallback onBack;
  final TbaClient? tbaClient;
  final MatchDirectory? matchDirectory;
  final CycleLogController? cycleLogController;
  final String eventKey;
  final PostMatchReportController? postMatchReportController;
  final UserRoleController? userRoleController;
  final int? myTeamNumber;
  final AssistantService? assistant;

  @override
  State<_MatchReview> createState() => _MatchReviewState();
}

class _MatchReviewState extends State<_MatchReview> {
  Future<List<TbaMatchVideo>>? _videosFuture;
  StrategySession? _strategySession;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _loadStrategySession();
  }

  void _loadVideos() {
    final client = widget.tbaClient;
    if (client == null) return;

    final tbaKey = _resolveTbaKey();
    if (tbaKey == null) return;

    _videosFuture = client
        .getMatch(tbaKey)
        .then((match) => match?.videos ?? const <TbaMatchVideo>[]);
  }

  String? _resolveTbaKey() {
    for (final e in widget.entries) {
      if (e.tbaMatchKey != null && e.tbaMatchKey!.isNotEmpty) {
        return e.tbaMatchKey;
      }
    }
    return null;
  }

  Future<void> _openReport() async {
    final controller = widget.postMatchReportController;
    if (controller == null || widget.eventKey.isEmpty) return;
    final teams = widget.entries.map((e) => e.teamNumber).toSet().toList()
      ..sort();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Match ${widget.matchId}',
          eventKey: widget.eventKey,
          matchId: widget.matchId,
          userRoleController: widget.userRoleController,
          cycleLogController: widget.cycleLogController,
          cycleLogTeams: teams,
          tbaClient: widget.tbaClient,
          myTeamNumber: widget.myTeamNumber,
          assistant: widget.assistant,
        ),
      ),
    );
  }

  Future<void> _loadStrategySession() async {
    final directory = widget.matchDirectory;
    if (directory == null) return;

    try {
      final matches = await directory.listMatches();
      for (final summary in matches) {
        if (summary.id == widget.matchId) {
          final session = await directory.loadMatch(summary.id);
          if (mounted) {
            setState(() => _strategySession = session);
          }
          break;
        }
      }
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tbaKey = _resolveTbaKey();
    final canReport =
        widget.postMatchReportController != null && widget.eventKey.isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'All matches',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Match ${widget.matchId}',
                        style: theme.textTheme.titleLarge,
                      ),
                      if (tbaKey != null)
                        Text(
                          tbaKey,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (canReport)
                  IconButton(
                    onPressed: _openReport,
                    icon: const Icon(Icons.rate_review_outlined),
                    tooltip: 'Post match report',
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _VideoSection(future: _videosFuture, tbaKey: tbaKey),
        ),
        if (widget.cycleLogController != null && widget.entries.isNotEmpty)
          SliverToBoxAdapter(
            child: _CycleLoggerSection(
              controller: widget.cycleLogController!,
              matchKey: widget.matchId,
              teams: widget.entries.map((e) => e.teamNumber).toSet().toList()
                ..sort(),
            ),
          ),
        if (_strategySession != null)
          SliverToBoxAdapter(
            child: _StrategyBoardSection(session: _strategySession!),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Scouting entries (${widget.entries.length})',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        if (widget.entries.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No scouting entries for this match.'),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _ScoutEntryCard(entry: widget.entries[index]),
              childCount: widget.entries.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _VideoSection extends StatelessWidget {
  const _VideoSection({required this.future, this.tbaKey});

  final Future<List<TbaMatchVideo>>? future;
  final String? tbaKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (future == null) {
      if (tbaKey == null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.link_off_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'These entries are not linked to the event schedule, '
                      'so there is no match to look a video up for. Select '
                      'the event on the Scout tab before saving entries; '
                      'the event card there shows the link for each entry.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.videocam_off_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "The Blue Alliance key is not set for your team yet, so "
                    'match video is off. It is set once for the whole team, '
                    'not per device; an admin adds it in Settings.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return FutureBuilder<List<TbaMatchVideo>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Could not load the video list from TBA. Check your '
                        'connection, then ask an admin to check the team TBA '
                        'key in the shared app config.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final videos = snapshot.data ?? const [];
        final youtube = videos.firstWhere(
          (v) => v.isYoutube,
          orElse: () => const TbaMatchVideo(type: '', key: ''),
        );

        if (youtube.key.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.videocam_off_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'The Blue Alliance has no video linked for this match. '
                        'Video appears here only when someone links it on TBA, '
                        'which does not happen for every match or event.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final url = youtube.youtubeUrl!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final opened = await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Could not open the video link.'),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Watch match video',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            'Opens YouTube',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StrategyBoardSection extends StatelessWidget {
  const _StrategyBoardSection({required this.session});

  final StrategySession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContent = session.strokesByPhase.values.any(
      (strokes) => strokes.isNotEmpty,
    );
    final hasMarkers = session.markersByPhase.values.any(
      (markers) => markers.isNotEmpty,
    );

    if (!hasContent && !hasMarkers && session.teamNumbers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.draw_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('Strategy board', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              Text(session.title, style: theme.textTheme.bodyMedium),
              Text(
                'Alliance: ${session.alliance}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (session.teamNumbers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Teams: ${session.teamNumbers.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (hasContent || hasMarkers)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_countStrokes(session)} strokes, ${_countMarkers(session)} markers across ${_countPhases(session)} phases',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _countStrokes(StrategySession s) =>
      s.strokesByPhase.values.fold(0, (sum, l) => sum + l.length);

  int _countMarkers(StrategySession s) =>
      s.markersByPhase.values.fold(0, (sum, l) => sum + l.length);

  int _countPhases(StrategySession s) {
    var count = 0;
    for (final phase in StrategyPhase.values) {
      if ((s.strokesByPhase[phase]?.isNotEmpty ?? false) ||
          (s.markersByPhase[phase]?.isNotEmpty ?? false)) {
        count++;
      }
    }
    return count;
  }
}

class _ScoutEntryCard extends StatelessWidget {
  const _ScoutEntryCard({required this.entry});

  final ScoutEntry entry;

  static bool _hasPhaseData(ScoutEntry entry, StrategyPhase phase) {
    final data = entry.byPhase[phase];
    if (data == null) return false;
    return data.score != 0 ||
        data.penalties != 0 ||
        data.counters.isNotEmpty ||
        data.notes.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalScore = entry.byPhase.values.fold(0, (sum, p) => sum + p.score);
    final totalPenalties = entry.byPhase.values.fold(
      0,
      (sum, p) => sum + p.penalties,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: StrategyPalette.surfaceStrongOf(context),
                    borderRadius: BorderRadius.circular(
                      StrategyPalette.radiusSm,
                    ),
                  ),
                  child: Text(
                    entry.effectiveAlliance,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: entry.effectiveAlliance == 'Red'
                          ? StrategyPalette.allianceRed
                          : StrategyPalette.allianceBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Team ${entry.teamNumber}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (entry.authorDisplayName.isNotEmpty)
                  Text(
                    entry.authorDisplayName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ScoreChip(
                  label: 'Score',
                  value: totalScore,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _ScoreChip(
                  label: 'Penalties',
                  value: totalPenalties,
                  color: theme.colorScheme.error,
                ),
              ],
            ),
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.notes,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            for (final phase in StrategyPhase.values)
              if (_hasPhaseData(entry, phase))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _PhaseDetailRow(
                    phase: phase,
                    data: entry.byPhase[phase]!,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceStrongOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PhaseDetailRow extends StatelessWidget {
  const _PhaseDetailRow({required this.phase, required this.data});

  final StrategyPhase phase;
  final ScoutPhaseData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    if (data.score != 0) parts.add('score: ${data.score}');
    if (data.penalties != 0) parts.add('pen: ${data.penalties}');
    for (final entry in data.counters.entries) {
      if (entry.value != 0) parts.add('${entry.key}: ${entry.value}');
    }

    final phaseFill = StrategyPalette.phaseColor(phase);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: phaseFill.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4, right: 6),
            decoration: BoxDecoration(color: phaseFill, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.name.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' | '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (data.notes.isNotEmpty)
                  Text(
                    data.notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleLogSyncPill extends StatelessWidget {
  const _CycleLogSyncPill({required this.failedWrites});

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

class _CycleLoggerSection extends StatefulWidget {
  const _CycleLoggerSection({
    required this.controller,
    required this.matchKey,
    required this.teams,
  });

  final CycleLogController controller;
  final String matchKey;
  final List<int> teams;

  @override
  State<_CycleLoggerSection> createState() => _CycleLoggerSectionState();
}

class _CycleLoggerSectionState extends State<_CycleLoggerSection> {
  final Stopwatch _watch = Stopwatch();
  final FocusNode _focus = FocusNode(debugLabel: 'cycle-logger');
  Timer? _ticker;
  late int _team = widget.teams.first;
  StrategyPhase _phase = StrategyPhase.teleop;

  bool get _started => _watch.isRunning || _watch.elapsedMilliseconds > 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _toggleArm() {
    setState(() {
      if (_watch.isRunning) {
        _watch.stop();
        _ticker?.cancel();
        _ticker = null;
      } else {
        _watch.start();
        _ticker ??= Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => setState(() {}),
        );
      }
    });
    _focus.requestFocus();
  }

  void _resetClock() {
    setState(() {
      _watch.stop();
      _watch.reset();
      _ticker?.cancel();
      _ticker = null;
    });
  }

  void _record(CycleEventKind kind) {
    if (!_started) return;
    HapticFeedback.selectionClick();
    widget.controller.recordEvent(
      matchKey: widget.matchKey,
      team: _team,
      kind: kind,
      offsetMs: _watch.elapsedMilliseconds,
      phase: _phase,
    );
    setState(() {});
  }

  Future<void> _clearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear cycle log for team $_team?'),
        content: const Text(
          'This removes every logged event for this team in this match. '
          'It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.clearLog(widget.matchKey, _team);
      if (mounted) setState(() {});
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _toggleArm();
      return KeyEventResult.handled;
    }
    final bindings = <LogicalKeyboardKey, CycleEventKind>{
      LogicalKeyboardKey.keyI: CycleEventKind.intake,
      LogicalKeyboardKey.keyS: CycleEventKind.score,
      LogicalKeyboardKey.keyF: CycleEventKind.feed,
      LogicalKeyboardKey.keyD: CycleEventKind.defense,
    };
    final kind = bindings[key];
    if (kind != null && _started) {
      _record(kind);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: _focus.requestFocus,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(theme, focused),
                      AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) {
                          if (!widget.controller.failedWrites.hasFailures) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _CycleLogSyncPill(
                                failedWrites: widget.controller.failedWrites,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _TeamStrip(
                        teams: widget.teams,
                        selected: _team,
                        onSelected: (t) => setState(() => _team = t),
                      ),
                      const SizedBox(height: 16),
                      _clockRow(theme),
                      const SizedBox(height: 16),
                      _PhaseStrip(
                        phase: _phase,
                        onSelected: (p) => setState(() => _phase = p),
                      ),
                      const SizedBox(height: 12),
                      _keyPad(),
                      const SizedBox(height: 8),
                      AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) => _LogSummary(
                          log: widget.controller.logFor(widget.matchKey, _team),
                          onClear: _clearLog,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, bool focused) {
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('Cycle logger', style: theme.textTheme.titleSmall),
        const Spacer(),
        Icon(
          Icons.keyboard_outlined,
          size: 18,
          color: focused
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          focused ? 'Keys active' : 'Click to use keys',
          style: theme.textTheme.labelSmall?.copyWith(
            color: focused
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _clockRow(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _fmtClock(_watch.elapsedMilliseconds),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        if (_started)
          TextButton(onPressed: _resetClock, child: const Text('Reset')),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _toggleArm,
          icon: Icon(
            _watch.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(_watch.isRunning ? 'Pause' : 'Arm'),
        ),
      ],
    );
  }

  Widget _keyPad() {
    return Row(
      children: [
        Expanded(
          child: _EventKeyButton(
            label: 'Intake',
            hint: 'I',
            icon: Icons.download_rounded,
            enabled: _started,
            onPressed: () => _record(CycleEventKind.intake),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EventKeyButton(
            label: 'Score',
            hint: 'S',
            icon: Icons.sports_score_rounded,
            enabled: _started,
            onPressed: () => _record(CycleEventKind.score),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EventKeyButton(
            label: 'Feed',
            hint: 'F',
            icon: Icons.volunteer_activism_rounded,
            enabled: _started,
            onPressed: () => _record(CycleEventKind.feed),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EventKeyButton(
            label: 'Defense',
            hint: 'D',
            icon: Icons.shield_outlined,
            enabled: _started,
            onPressed: () => _record(CycleEventKind.defense),
          ),
        ),
      ],
    );
  }
}

String _fmtClock(int ms) {
  final tenths = (ms ~/ 100) % 10;
  final totalSeconds = ms ~/ 1000;
  final seconds = totalSeconds % 60;
  final minutes = totalSeconds ~/ 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}

class _TeamStrip extends StatelessWidget {
  const _TeamStrip({
    required this.teams,
    required this.selected,
    required this.onSelected,
  });

  final List<int> teams;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final team in teams)
          ChoiceChip(
            label: Text('$team'),
            selected: team == selected,
            onSelected: (_) => onSelected(team),
          ),
      ],
    );
  }
}

class _PhaseStrip extends StatelessWidget {
  const _PhaseStrip({required this.phase, required this.onSelected});

  final StrategyPhase phase;
  final ValueChanged<StrategyPhase> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final value in StrategyPhase.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _chip(theme, value),
          ),
      ],
    );
  }

  Widget _chip(ThemeData theme, StrategyPhase value) {
    final selected = value == phase;
    return ChoiceChip(
      label: Text(value.label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: StrategyPalette.phaseColor(value),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: selected
            ? StrategyPalette.onPhaseColor(value)
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EventKeyButton extends StatelessWidget {
  const _EventKeyButton({
    required this.label,
    required this.hint,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String hint;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        minimumSize: const Size(0, 56),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelMedium),
          Text(
            hint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogSummary extends StatelessWidget {
  const _LogSummary({required this.log, required this.onClear});

  final CycleLog? log;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = log?.events ?? const <CycleEvent>[];
    if (events.isEmpty) {
      return Text(
        'Arm the clock, then press I / S / F / D as the robot cycles.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final mean = log?.meanCycleMs;
    final recent = events.reversed.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              mean == null
                  ? '${events.length} events'
                  : '${(mean / 1000).toStringAsFixed(1)}s avg cycle · ${events.length} events',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final event in recent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: StrategyPalette.phaseColor(event.phase)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
                ),
                child: Text(
                  '${_kindLabel(event.kind)} ${_fmtClock(event.offsetMs)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _kindLabel(CycleEventKind kind) => switch (kind) {
    CycleEventKind.intake => 'Intake',
    CycleEventKind.score => 'Score',
    CycleEventKind.feed => 'Feed',
    CycleEventKind.defense => 'Defense',
  };
}
