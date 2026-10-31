import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../models/cycle_log.dart';
import '../models/trex_trait.dart';
import '../models/trex_trait_report.dart';
import '../models/user_role.dart';
import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/prescout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/models/team_analysis.dart';
import '../scouting/services/prescout_summary_stats.dart';
import '../scouting/services/robot_type.dart';
import '../scouting/services/scouting_analysis.dart';
import '../scouting/services/team_summary_stats.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/prescouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant/scoring_trend_analysis.dart';
import '../services/statbotics/team_history_service.dart';
import '../services/team_avatar_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/event_controller.dart';
import '../state/event_stats_controller.dart';
import '../state/post_match_report_controller.dart';
import '../state/trex_trait_report_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/match_schedule_row.dart';
import 'analysis_view.dart';
import 'comment_digest_card.dart';
import 'freshness_pill.dart';
import 'match_info_view.dart' show mostRecentPitEntryByTeam;
import 'match_hub/match_hub_launcher.dart';
import 'pit_entry_card.dart';
import 'pit_scouting_screen.dart';
import 'scoring_trend_card.dart';
import 'team_brief_card.dart';

class TeamHubScreen extends StatelessWidget {
  const TeamHubScreen({
    required this.teamNumber,
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    this.statsController,
    this.cycleLogController,
    this.assistant,
    this.teamHistory,
    this.canPublishSummaries = false,
    this.pitScoutingController,
    this.pitScoutConfigController,
    this.prescoutingController,
    this.trexTraitReportController,
    this.postMatchReportController,
    this.userRoleController,
    this.teamAvatarService,
    super.key,
  });

  final int teamNumber;
  final EventController eventController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;

  final EventStatsController? statsController;
  final CycleLogController? cycleLogController;

  final AssistantService? assistant;

  final TeamHistoryService? teamHistory;

  final bool canPublishSummaries;

  bool get _canPublish =>
      userRoleController?.roles.canPublishSummaries ?? canPublishSummaries;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;
  final PrescoutingController? prescoutingController;
  final TrexTraitReportController? trexTraitReportController;
  final PostMatchReportController? postMatchReportController;
  final UserRoleController? userRoleController;
  final TeamAvatarService? teamAvatarService;

  static const double wideBreakpoint = 840;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        scoutingController,
        configController,
        eventController,
        statsController,
        cycleLogController,
        pitScoutingController,
        pitScoutConfigController,
        prescoutingController,
        trexTraitReportController,
        userRoleController,
      ]),
      builder: (context, _) {
        final data = _TeamHubData(this);
        final left = data.leftSections();
        final right = data.rightSections();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Text('Team $teamNumber'),
            actions: [
              FreshnessPill(
                scoutingController: scoutingController,
                eventController: eventController,
                pitScoutingController: pitScoutingController,
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= wideBreakpoint;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1100 : 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(data: data),
                        const SizedBox(height: 16),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _SectionColumn(left)),
                              const SizedBox(width: 24),
                              Expanded(child: _SectionColumn(right)),
                            ],
                          )
                        else
                          _SectionColumn([...left, ...right]),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TeamHubData {
  _TeamHubData(this.hub) {
    final team = hub.teamNumber;
    final scouting = hub.scoutingController;
    final config = hub.configController.config;
    entries = scouting.entries.where((e) => e.teamNumber == team).toList();
    analysis = ScoutingAnalysis.analyzeTeam(team, entries, config: config);
    final rows = TeamSummaryStats.build(
      entries,
      teamNumbers: [team],
      config: config,
    );
    summary = rows.single;
    climbCounts = TeamSummaryStats.climbCounts(entries, config: config);
    notes = ScoutingAnalysis.notesForTeam(team, entries);
    reportGroups = ScoutingAnalysis.reportsForTeam(team, entries, config);
    trend = ScoringTrendAnalysis.series(team, entries, config: config);

    final logs = hub.cycleLogController?.logs ?? const <CycleLog>[];
    cycleLogs = logs
        .where((log) => log.team == team && log.events.isNotEmpty)
        .toList();

    final pitEntries = hub.pitScoutingController?.entries;
    pitEntry = mostRecentPitEntryByTeam(pitEntries)[team];

    final prescout =
        hub.prescoutingController?.entries ?? const <PrescoutEntry>[];
    final prescoutRows = PrescoutSummaryStats.build(
      prescout.where((e) => e.teamNumber == team),
      teamNumbers: [team],
    );
    prescoutRow = prescoutRows.single;
    prescoutNotes = PrescoutSummaryStats.notesForTeam(team, prescout);

    final trex = hub.trexTraitReportController;
    final reports = trex?.reports ?? const <TrexTraitReport>[];
    trexReports = reports
        .where((r) => r.teamNumber == team && r.report.trim().isNotEmpty)
        .toList();
    trexReports.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final schedule = sortMatchesByCompLevel(hub.eventController.matches);
    matches = schedule.where((m) => m.allTeams.contains(team)).toList();
    final teamEvents = hub.eventController.displayTeams;
    teamEvent = teamEvents.where((te) => te.team == team).firstOrNull;
  }

  final TeamHubScreen hub;
  late final List<ScoutEntry> entries;
  late final TeamAnalysis analysis;
  late final TeamSummaryRow summary;
  late final Map<String, SuccessCount> climbCounts;
  late final List<TeamNote> notes;
  late final List<TeamReportGroup> reportGroups;
  late final List<MatchScorePoint> trend;
  late final List<CycleLog> cycleLogs;
  late final PitScoutEntry? pitEntry;
  late final PrescoutSummaryRow prescoutRow;
  late final List<TeamNote> prescoutNotes;
  late final List<TrexTraitReport> trexReports;
  late final List<StatboticsMatch> matches;
  late final StatboticsTeamEvent? teamEvent;

  String get eventKey => hub.eventController.eventKey;

  bool get hasPit =>
      pitEntry != null &&
      hub.pitScoutingController != null &&
      hub.pitScoutConfigController != null;

  List<Widget> leftSections() {
    return [
      _Section(
        title: 'Event stats',
        child: _StatsBody(data: this),
      ),
      if (analysis.hasData)
        _Section(
          title: 'By phase',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhaseScoreBars(analysis: analysis),
              const SizedBox(height: 12),
              for (final phase in StrategyPhase.values)
                PhaseDetail(phase: phase, stats: analysis.phaseStats(phase)),
            ],
          ),
        ),
      if (analysis.hasData && eventKey.isNotEmpty)
        ScoringTrendCard(
          assistant: hub.assistant,
          teamNumber: hub.teamNumber,
          eventKey: eventKey,
          series: trend,
          history: hub.teamHistory,
          cycleLogs: cycleLogs,
          canPublish: hub._canPublish,
        ),
      if (analysis.hasData)
        TeamBriefCard(
          assistant: hub.assistant,
          teamNumber: hub.teamNumber,
          history: hub.teamHistory,
          canPublish: hub._canPublish,
        ),
      if (cycleLogs.isNotEmpty)
        _Section(
          title: 'Cycle times (film)',
          child: CycleTimesSection(logs: cycleLogs),
        ),
    ];
  }

  List<Widget> rightSections() {
    return [
      _Section(
        title: 'Matches',
        child: _MatchList(data: this),
      ),
      if (notes.isNotEmpty || reportGroups.isNotEmpty)
        _Section(
          title: 'Scout comments',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notes.isNotEmpty && eventKey.isNotEmpty)
                CommentDigestCard(
                  assistant: hub.assistant,
                  teamNumber: hub.teamNumber,
                  eventKey: eventKey,
                  notes: notes,
                  canPublish: hub._canPublish,
                ),
              if (notes.isNotEmpty) TeamCommentList(notes: notes),
              for (final group in reportGroups)
                ReportGroupSection(group: group),
            ],
          ),
        ),
      if (hasPit)
        _Section(
          title: 'Pit scouting',
          child: PitEntryCard(
            entry: pitEntry!,
            controller: hub.pitScoutingController!,
            config: hub.pitScoutConfigController!.config,
            initiallyExpanded: true,
          ),
        ),
      if (trexReports.isNotEmpty)
        _Section(
          title: 'T-Rex traits',
          child: _TrexList(reports: trexReports),
        ),
      if (prescoutRow.matchesRecorded > 0)
        _PrescoutSection(row: prescoutRow, notes: prescoutNotes),
    ];
  }
}

class _SectionColumn extends StatelessWidget {
  const _SectionColumn(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 24),
          children[i],
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: StrategyPalette.borderOf(context)),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final _TeamHubData data;

  String? get _standing {
    final hub = data.hub;
    final stats = hub.statsController;
    final tbaRank = stats?.rankFor(hub.teamNumber);
    final opr = stats?.oprFor(hub.teamNumber);
    final epa = data.teamEvent?.epa.totalPoints;
    final parts = <String>[
      if (tbaRank != null) 'TBA rank #$tbaRank',
      if (opr != null) 'OPR ${opr.toStringAsFixed(1)}',
      if (epa != null) 'EPA ${epa.toStringAsFixed(1)}',
      if (data.teamEvent != null) data.teamEvent!.record,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get _pitFlags {
    final config = data.hub.pitScoutConfigController?.config;
    ScoutConfigField? driveTrain;
    for (final field in config?.allFields ?? const <ScoutConfigField>[]) {
      if (field.code == RobotType.driveTrainCode) driveTrain = field;
    }
    final flags = RobotType.composeFrom(
      data.pitEntry,
      driveTrainField: driveTrain,
    );
    return flags.isEmpty ? null : flags;
  }

  @override
  Widget build(BuildContext context) {
    final hub = data.hub;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final nameStyle = text.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final nickname = hub.eventController.teamNicknames[hub.teamNumber];
    final standing = _standing;
    final pitFlags = _pitFlags;
    final canCompare =
        ScoutingAnalysis.teamNumbers(hub.scoutingController.entries).length > 1;
    final pitScouting = hub.pitScoutingController;
    final pitConfig = hub.pitScoutConfigController;
    final actionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TeamAvatar(
              teamNumber: hub.teamNumber,
              service: hub.teamAvatarService,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nickname != null && nickname.isNotEmpty)
                    Text(nickname, style: nameStyle),
                  if (standing != null) Text(standing, style: muted),
                  if (pitFlags != null) Text('Pit: $pitFlags', style: muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canCompare)
              OutlinedButton.icon(
                style: actionStyle,
                onPressed: () => _compare(context),
                icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: const Text('Compare'),
              ),
            if (pitScouting != null && pitConfig != null)
              OutlinedButton.icon(
                style: actionStyle,
                onPressed: () => _pitScout(context, pitScouting, pitConfig),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Pit scout'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _compare(BuildContext context) async {
    final hub = data.hub;
    final opponent = await pickOpponentTeam(
      context,
      controller: hub.scoutingController,
      configController: hub.configController,
      excludeTeam: hub.teamNumber,
    );
    if (opponent == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompareTeamsScreen(
          controller: hub.scoutingController,
          configController: hub.configController,
          teamA: hub.teamNumber,
          teamB: opponent,
        ),
      ),
    );
  }

  Future<void> _pitScout(
    BuildContext context,
    PitScoutingController controller,
    PitScoutConfigController configController,
  ) {
    final hub = data.hub;
    final canEdit = hub.userRoleController?.roles.canEditAnyEntry ?? false;
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PitScoutingScreen(
          controller: controller,
          configController: configController,
          canEditAnyEntry: canEdit,
          initialTeamNumber: hub.teamNumber,
        ),
      ),
    );
  }
}

class _TeamAvatar extends StatefulWidget {
  const _TeamAvatar({required this.teamNumber, required this.service});

  final int teamNumber;
  final TeamAvatarService? service;

  @override
  State<_TeamAvatar> createState() => _TeamAvatarState();
}

class _TeamAvatarState extends State<_TeamAvatar> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.service?.avatarFor(widget.teamNumber);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.groups_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceStrongOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: _bytes == null
          ? fallback
          : FutureBuilder<Uint8List?>(
              future: _bytes,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                return bytes == null
                    ? fallback
                    : Image.memory(bytes, fit: BoxFit.contain);
              },
            ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.data});

  final _TeamHubData data;

  @override
  Widget build(BuildContext context) {
    final analysis = data.analysis;
    final summary = data.summary;
    if (!analysis.hasData) {
      return Text(
        'No entries recorded for this team yet.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final rates = data.climbCounts.entries.where((e) => e.value.total > 0);
    String? sd;
    if (analysis.entryCount > 1) sd = formatStat(analysis.scoreStdDev);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatTable(
          rows: [
            _StatRow(
              'Total score',
              mean: formatStat(analysis.meanTotalScore),
              iqm: formatStat(analysis.iqmTotalScore),
              sd: sd,
              n: analysis.entryCount,
            ),
            _StatRow(
              'Teleop fuel',
              mean: _stat(summary.meanTeleop),
              iqm: _stat(summary.iqmTeleop),
              max: _stat(summary.maxTeleop),
              sd: _stat(summary.sdTeleop),
              n: summary.teleopSamples,
            ),
            _StatRow(
              'Auto fuel',
              mean: _stat(summary.meanAuto),
              iqm: _stat(summary.iqmAuto),
              max: _stat(summary.maxAuto),
              sd: _stat(summary.sdAuto),
              n: summary.autoSamples,
            ),
          ],
        ),
        if (rates.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final entry in rates)
                _RateText(label: entry.key, count: entry.value),
            ],
          ),
        ],
      ],
    );
  }

  static String? _stat(double? v) => v == null ? null : formatStat(v);
}

class _StatRow {
  const _StatRow(this.label, {this.mean, this.iqm, this.max, this.sd, this.n});

  final String label;
  final String? mean;
  final String? iqm;
  final String? max;
  final String? sd;
  final int? n;
}

class _StatTable extends StatelessWidget {
  const _StatTable({required this.rows});

  final List<_StatRow> rows;

  static Widget _cell(String value, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(value, style: style, textAlign: TextAlign.end),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final header = text.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
        5: FlexColumnWidth(),
      },
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            _cell('Mean', header),
            _cell('IQM', header),
            _cell('Max', header),
            _cell('SD', header),
            _cell('n', header),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(row.label, style: text.bodyMedium),
              ),
              _cell(row.mean ?? '--', text.bodyMedium),
              _cell(row.iqm ?? '--', text.bodyMedium),
              _cell(row.max ?? '--', text.bodyMedium),
              _cell(row.sd ?? '--', text.bodyMedium),
              _cell(row.n?.toString() ?? '--', text.bodyMedium),
            ],
          ),
      ],
    );
  }
}

class _RateText extends StatelessWidget {
  const _RateText({required this.label, required this.count});

  final String label;
  final SuccessCount count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Text('$label ${count.successes} / ${count.total}', style: style);
  }
}

class _MatchList extends StatelessWidget {
  const _MatchList({required this.data});

  final _TeamHubData data;

  @override
  Widget build(BuildContext context) {
    final nicknames = data.hub.eventController.teamNicknames;
    if (data.matches.isEmpty) {
      return Text(
        'No scheduled matches for this team.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        for (final match in data.matches)
          MatchScheduleRow(
            match: match,
            nicknames: nicknames,
            onTap: MatchHubScope.opener(context, match),
          ),
      ],
    );
  }
}

class _TrexList extends StatelessWidget {
  const _TrexList({required this.reports});

  final List<TrexTraitReport> reports;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final report in reports)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.report.trim(), style: text.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    _context(report),
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

  static String _context(TrexTraitReport report) {
    return <String>[
      TrexTrait.byKey(report.trait)?.label ?? report.trait,
      if (report.matchNumber > 0) 'Match ${report.matchNumber}',
      if (report.authorDisplayName.isNotEmpty) report.authorDisplayName,
    ].join(' · ');
  }
}

class _PrescoutSection extends StatelessWidget {
  const _PrescoutSection({required this.row, required this.notes});

  final PrescoutSummaryRow row;
  final List<TeamNote> notes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rates = <(String, double?)>[
      ('Auto climb', row.autoClimbRate),
      ('Low climb', row.lowClimbRate),
      ('Mid climb', row.middleClimbRate),
      ('High climb', row.highClimbRate),
    ];
    String stat(double? value) => value == null ? '--' : formatStat(value);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Prescout',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            'From watched matches at other events. Not part of the event '
            'stats above.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _StatTable(
            rows: [
              _StatRow(
                'Teleop fuel',
                iqm: stat(row.iqmTeleopFuel),
                max: stat(row.maxTeleopFuel),
                n: row.matchesRecorded,
              ),
              _StatRow(
                'Auto fuel',
                iqm: stat(row.iqmAutoFuel),
                max: stat(row.maxAutoFuel),
                n: row.matchesRecorded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if (row.avgFuelAccuracy != null)
                Text(
                  'Fuel accuracy ${stat(row.avgFuelAccuracy)}',
                  style: text.bodySmall,
                ),
              for (final (label, rate) in rates)
                if (rate != null)
                  Text(
                    '$label ${(rate * 100).round()}%',
                    style: text.bodySmall,
                  ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            TeamCommentList(notes: notes),
          ],
        ],
      ),
    );
  }
}
