import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../models/post_match_report.dart';
import '../models/user_role.dart';
import '../services/assistant/assistant_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/failed_write_tracker.dart';
import '../state/post_match_report_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/sync_status_pill.dart';
import 'post_match_analysis_card.dart';

class PostMatchReportScreen extends StatefulWidget {
  const PostMatchReportScreen({
    required this.controller,
    required this.matchLabel,
    required this.eventKey,
    required this.matchId,
    this.userRoleController,
    this.cycleLogController,
    this.cycleLogTeams = const <int>[],
    this.tbaClient,
    this.myTeamNumber,
    this.assistant,
    super.key,
  });

  final PostMatchReportController controller;
  final String matchLabel;
  final String eventKey;
  final String matchId;

  final UserRoleController? userRoleController;

  final CycleLogController? cycleLogController;

  final List<int> cycleLogTeams;

  final TbaClient? tbaClient;

  final int? myTeamNumber;

  final AssistantService? assistant;

  @override
  State<PostMatchReportScreen> createState() => _PostMatchReportScreenState();
}

class _PostMatchReportScreenState extends State<PostMatchReportScreen> {
  late final TextEditingController _autoController;
  late final TextEditingController _teleopController;
  late final TextEditingController _endgameController;
  late final TextEditingController _notesController;

  late PostMatchReport _loaded;

  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loaded = widget.controller.reportFor(widget.eventKey, widget.matchId);
    _autoController = TextEditingController(text: _loaded.auto);
    _teleopController = TextEditingController(text: _loaded.teleop);
    _endgameController = TextEditingController(text: _loaded.endgame);
    _notesController = TextEditingController(text: _loaded.notes);
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_dirty) return;
    final latest = widget.controller.reportFor(widget.eventKey, widget.matchId);
    if (latest.updatedAt == _loaded.updatedAt) {
      setState(() {});
      return;
    }
    setState(() {
      _loaded = latest;
      _autoController.text = latest.auto;
      _teleopController.text = latest.teleop;
      _endgameController.text = latest.endgame;
      _notesController.text = latest.notes;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _autoController.dispose();
    _teleopController.dispose();
    _endgameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _canEdit =>
      widget.userRoleController?.roles.canEditScoutConfig ?? false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await widget.controller.save(
      eventKey: widget.eventKey,
      matchId: widget.matchId,
      auto: _autoController.text,
      teleop: _teleopController.text,
      endgame: _endgameController.text,
      notes: _notesController.text,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    setState(() {
      _saving = false;
      _dirty = false;
      _loaded = widget.controller.reportFor(widget.eventKey, widget.matchId);
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.controller.reportFor(widget.eventKey, widget.matchId);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.matchLabel} report')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _PurposeLine(),
                  const SizedBox(height: 16),
                  if (widget.controller.failedWrites.hasFailures) ...[
                    _PostMatchReportSyncPill(
                      failedWrites: widget.controller.failedWrites,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (!_canEdit) const _ReadOnlyNotice(),
                  if (widget.cycleLogController != null &&
                      widget.cycleLogTeams.isNotEmpty)
                    _CycleLogNote(
                      cycleLogController: widget.cycleLogController!,
                      matchId: widget.matchId,
                      teams: widget.cycleLogTeams,
                    ),
                  _Section(
                    label: 'Auto',
                    controller: _autoController,
                    enabled: _canEdit,
                    onChanged: _markDirty,
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    label: 'Teleop',
                    controller: _teleopController,
                    enabled: _canEdit,
                    onChanged: _markDirty,
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    label: 'Endgame',
                    controller: _endgameController,
                    enabled: _canEdit,
                    onChanged: _markDirty,
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    label: 'Notes',
                    hint:
                        'Anything that does not fit one phase: penalties, '
                        'breakdowns, what to watch for next time.',
                    controller: _notesController,
                    enabled: _canEdit,
                    onChanged: _markDirty,
                  ),
                  if (report.authorDisplayName.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Last written by ${report.authorDisplayName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StrategyPalette.mutedTextOf(context),
                      ),
                    ),
                  ],
                  if (widget.tbaClient != null || widget.assistant != null) ...[
                    const SizedBox(height: 24),
                    _AnalysisSection(
                      eventKey: widget.eventKey,
                      matchId: widget.matchId,
                      report: report,
                      tbaClient: widget.tbaClient,
                      myTeamNumber: widget.myTeamNumber,
                      assistant: widget.assistant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_canEdit)
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: InputDecoration(
            hintText: hint ?? 'What happened in $label, in your own words.',
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(StrategyPalette.radiusSm),
              ),
            ),
            alignLabelWithHint: true,
          ),
          textAlignVertical: TextAlignVertical.top,
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _PurposeLine extends StatelessWidget {
  const _PurposeLine();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Text(
      'The strategy lead\'s account of what happened to our own robot this '
      'match. Any member can read it; strategy and admin can write it.',
      style: style?.copyWith(color: StrategyPalette.mutedTextOf(context)),
    );
  }
}

class _PostMatchReportSyncPill extends StatelessWidget {
  const _PostMatchReportSyncPill({required this.failedWrites});

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

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: StrategyPalette.surfaceOf(context),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: const BorderRadius.all(
            Radius.circular(StrategyPalette.radiusSm),
          ),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.lock_outline, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('Only strategy leads and admins can edit this.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleLogNote extends StatelessWidget {
  const _CycleLogNote({
    required this.cycleLogController,
    required this.matchId,
    required this.teams,
  });

  final CycleLogController cycleLogController;
  final String matchId;
  final List<int> teams;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cycleLogController,
      builder: (context, _) {
        final logged = <int>[
          for (final team in teams)
            if (cycleLogController.logFor(matchId, team) != null) team,
        ];
        if (logged.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.movie_creation_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A cycle log already exists for team'
                  '${logged.length > 1 ? 's' : ''} '
                  '${logged.join(', ')} in this match -- see Film review.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalysisSection extends StatefulWidget {
  const _AnalysisSection({
    required this.eventKey,
    required this.matchId,
    required this.report,
    this.tbaClient,
    this.myTeamNumber,
    this.assistant,
  });

  final String eventKey;
  final String matchId;
  final PostMatchReport report;
  final TbaClient? tbaClient;
  final int? myTeamNumber;
  final AssistantService? assistant;

  @override
  State<_AnalysisSection> createState() => _AnalysisSectionState();
}

class _AnalysisSectionState extends State<_AnalysisSection> {
  Future<TbaScheduleMatch?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AnalysisSection old) {
    super.didUpdateWidget(old);
    if (old.eventKey != widget.eventKey || old.matchId != widget.matchId) {
      _load();
    }
  }

  void _load() {
    final client = widget.tbaClient;
    _future = client == null
        ? Future<TbaScheduleMatch?>.value()
        : _fetch(client);
  }

  Future<TbaScheduleMatch?> _fetch(TbaClient client) async {
    if (widget.eventKey.isEmpty || widget.matchId.isEmpty) return null;
    final key = '${widget.eventKey}_${widget.matchId}';
    try {
      final matches = await client.getEventMatches(widget.eventKey);
      for (final match in matches) {
        if (match.key == key) return match;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TbaScheduleMatch?>(
      future: _future,
      builder: (context, snapshot) {
        final match = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Analysis', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'The app fills this in; nothing here is written by a person.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
            ),
            const SizedBox(height: 8),
            if (match != null && match.isPlayed) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.emoji_events_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resultSummary(match),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.assistant != null)
              PostMatchAnalysisCard(
                assistant: widget.assistant,
                eventKey: widget.eventKey,
                matchId: widget.matchId,
                report: widget.report,
                tbaMatch: match,
                myTeamNumber: widget.myTeamNumber,
              ),
          ],
        );
      },
    );
  }

  String _resultSummary(TbaScheduleMatch match) {
    final ourAlliance = _ourAlliance(match);
    if (ourAlliance == null) {
      return 'TBA result: red ${match.redScore} - blue ${match.blueScore}.';
    }
    final ourScore = ourAlliance == 'red' ? match.redScore : match.blueScore;
    final theirScore = ourAlliance == 'red' ? match.blueScore : match.redScore;
    final outcome = match.isTie
        ? 'Tied'
        : match.winningAlliance == ourAlliance
        ? 'Won'
        : 'Lost';
    return 'TBA result: $outcome $ourScore - $theirScore.';
  }

  String? _ourAlliance(TbaScheduleMatch match) {
    final team = widget.myTeamNumber;
    if (team == null) return null;
    if (match.redTeams.contains(team)) return 'red';
    if (match.blueTeams.contains(team)) return 'blue';
    return null;
  }
}
