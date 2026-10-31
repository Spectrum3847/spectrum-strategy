import 'package:flutter/material.dart';

import '../../models/match_brief.dart';
import '../../models/match_forecast.dart';
import '../../models/match_preview.dart';
import '../../scouting/services/match_hub_stats.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/alliance_tag.dart';
import '../../widgets/empty_state.dart';
import 'match_hub_launcher.dart';
import 'match_hub_widgets.dart';

class MatchHubBriefTab extends StatefulWidget {
  const MatchHubBriefTab({
    required this.launcher,
    required this.data,
    super.key,
  });

  final MatchHubLauncher launcher;
  final MatchHubData data;

  @override
  State<MatchHubBriefTab> createState() => _MatchHubBriefTabState();
}

class _MatchHubBriefTabState extends State<MatchHubBriefTab>
    with AutomaticKeepAliveClientMixin {
  final _points = TextEditingController();
  late MatchBrief _loaded;
  bool _dirty = false;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  MatchHubLauncher get _launcher => widget.launcher;

  @override
  void initState() {
    super.initState();
    _loaded = _launcher.briefFor(widget.data.match);
    _points.text = _loaded.keyPoints;
    _launcher.briefController?.addListener(_onBriefChanged);
  }

  @override
  void dispose() {
    _launcher.briefController?.removeListener(_onBriefChanged);
    _points.dispose();
    super.dispose();
  }

  void _onBriefChanged() {
    if (!mounted) return;

    if (_dirty) return;
    final latest = _launcher.briefFor(widget.data.match);
    if (latest.updatedAt != _loaded.updatedAt) {
      _loaded = latest;
      _points.text = latest.keyPoints;
    }
    setState(() {});
  }

  Future<void> _save({bool? ready}) async {
    final briefs = _launcher.briefController;
    if (briefs == null) return;
    setState(() => _saving = true);
    final saved = await briefs.save(
      eventKey: _launcher.eventController.eventKey,
      matchId: _launcher.matchIdOf(widget.data.match),
      keyPoints: _points.text.trim(),
      ready: ready,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) {
        _dirty = false;
        _loaded = _launcher.briefFor(widget.data.match);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = widget.data;
    if (data.ourAlliance == null) {
      return const EmptyState(
        icon: Icons.assignment_outlined,
        message:
            'Briefs cover the matches our team plays.\n'
            'Set your team number in Settings if this one should be ours.',
      );
    }
    final briefs = _launcher.briefController;
    final brief = _launcher.briefFor(data.match);
    final events = _launcher.eventController;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (briefs != null && _launcher.canEdit) ...<Widget>[
              HubSection(
                title: 'Write the brief',
                trailing: MatchBriefSyncChip(status: briefs.syncStatus),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _points,
                      maxLength: MatchBrief.maxKeyPointsLength,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Key points for partners and the coach',
                      ),
                      onChanged: (_) => setState(() => _dirty = true),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: _dirty && !_saving ? _save : null,
                          child: const Text('Save'),
                        ),
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _save(ready: !brief.ready),
                          child: Text(
                            brief.ready ? 'Mark as draft' : 'Mark ready',
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Robot plans are written on the Plan tab.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StrategyPalette.mutedTextOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        CoachBriefScreen(launcher: _launcher, data: data),
                  ),
                ),
                icon: const Icon(Icons.fullscreen_rounded, size: 18),
                label: const Text('Open full screen'),
              ),
            ),
            const SizedBox(height: 12),
            CoachBriefView(
              data: data,
              brief: brief,
              forecasts: events.forecastsFor(data.match.key),
              onOpenTeam: (team) => _launcher.openTeam(context, team),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachBriefView extends StatelessWidget {
  const CoachBriefView({
    required this.data,
    required this.brief,
    this.forecasts = const <MatchForecast>[],
    this.onOpenTeam,
    super.key,
  });

  final MatchHubData data;
  final MatchBrief brief;
  final List<MatchForecast> forecasts;
  final ValueChanged<int>? onOpenTeam;

  @override
  Widget build(BuildContext context) {
    final ours = data.ourAlliance!;
    final theirs = ours == 'Red' ? 'Blue' : 'Red';
    final title = Theme.of(context).textTheme.titleMedium;
    final large = title?.copyWith(fontWeight: FontWeight.w400);
    return LayoutBuilder(
      builder: (context, constraints) {
        final plan = _Panel(
          alliance: ours,
          heading: 'Our alliance',
          children: <Widget>[
            for (final team in data.ourTeams)
              _RobotBlock(
                team: team,
                titleStyle: title,
                onOpenTeam: onOpenTeam,
                lines: <String>[
                  brief.planFor(team.teamNumber).isEmpty
                      ? 'No plan written'
                      : brief.planFor(team.teamNumber),
                ],
                textStyle: large,
              ),
          ],
        );
        final opponents = _Panel(
          alliance: theirs,
          heading: 'Opponents',
          children: <Widget>[
            _ThreatLine(teams: data.opponentTeams, style: large),
            for (final team in data.opponentTeams)
              _RobotBlock(
                team: team,
                titleStyle: title,
                onOpenTeam: onOpenTeam,
                plan: brief.planFor(team.teamNumber),
                lines: data.factsFor(team),
                textStyle: large,
                bullets: true,
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              ours: ours,
              brief: brief,
              forecasts: forecasts,
              style: title,
            ),
            const SizedBox(height: 12),
            HubSection(
              title: 'Key points',
              child: Text(
                brief.keyPoints.trim().isEmpty
                    ? 'None written'
                    : brief.keyPoints.trim(),
                style: large,
              ),
            ),
            const SizedBox(height: 12),
            if (constraints.maxWidth >= 760)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: plan),
                  const SizedBox(width: 12),
                  Expanded(child: opponents),
                ],
              )
            else ...<Widget>[plan, const SizedBox(height: 12), opponents],
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ours,
    required this.brief,
    required this.forecasts,
    required this.style,
  });

  final String ours;
  final MatchBrief brief;
  final List<MatchForecast> forecasts;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final ready = brief.ready;
    final muted = StrategyPalette.mutedTextOf(context);
    return HubSection(
      title: 'Match brief',
      trailing: _ReadyTag(ready: ready),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text('We are', style: style),
              AllianceTag(alliance: ours),
            ],
          ),
          for (final forecast in forecasts)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_forecastLine(forecast), style: style),
            ),
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Draft: the strategy lead has not marked this ready.',
                style: style?.copyWith(color: muted),
              ),
            ),
          if (brief.authorDisplayName.isNotEmpty)
            Text(
              'Written by ${brief.authorDisplayName}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }

  String _forecastLine(MatchForecast forecast) {
    final weAreRed = ours == 'Red';
    final ourScore = weAreRed ? forecast.redScore : forecast.blueScore;
    final theirScore = weAreRed ? forecast.blueScore : forecast.redScore;
    final ourWin = weAreRed
        ? forecast.redWinProbability
        : 1 - forecast.redWinProbability;
    return '${forecast.source.label} forecast: we score ${ourScore.round()}, '
        'they score ${theirScore.round()}, our win chance '
        '${(ourWin * 100).round()}%';
  }
}

class _ReadyTag extends StatelessWidget {
  const _ReadyTag({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final fill = ready
        ? StrategyPalette.chipSelectedOf(context)
        : StrategyPalette.chipUnselectedOf(context);
    final ink = ready
        ? StrategyPalette.onChipSelectedOf(context)
        : StrategyPalette.onChipUnselectedOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ready ? Icons.check_circle_outline : Icons.edit_note_rounded,
            size: 16,
            color: ink,
          ),
          const SizedBox(width: 4),
          Text(
            ready ? 'Ready' : 'Draft',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.alliance,
    required this.heading,
    required this.children,
  });

  final String alliance;
  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return HubSection(
      title: heading,
      trailing: AllianceTag(alliance: alliance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ThreatLine extends StatelessWidget {
  const _ThreatLine({required this.teams, required this.style});

  final List<MatchPreviewTeam> teams;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    MatchPreviewTeam? top;
    for (final team in teams) {
      final epa = team.epaTotal;
      if (epa == null) continue;
      if (top == null || epa > top.epaTotal!) top = team;
    }
    if (top == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Highest EPA: ${top.teamNumber} (${top.epaTotal!.toStringAsFixed(1)})',
        style: style,
      ),
    );
  }
}

class _RobotBlock extends StatelessWidget {
  const _RobotBlock({
    required this.team,
    required this.titleStyle,
    required this.textStyle,
    required this.lines,
    this.onOpenTeam,
    this.bullets = false,
    this.plan = '',
  });

  final MatchPreviewTeam team;
  final TextStyle? titleStyle;
  final TextStyle? textStyle;
  final List<String> lines;
  final ValueChanged<int>? onOpenTeam;
  final bool bullets;

  final String plan;

  @override
  Widget build(BuildContext context) {
    final open = onOpenTeam;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          HubTeamLink(
            team: team.teamNumber,
            nickname: team.nickname,
            onTap: open == null ? null : () => open(team.teamNumber),
            style: titleStyle,
          ),
          if (plan.isNotEmpty)
            Text(
              'Plan: $plan',
              style: textStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
          for (final line in lines)
            Text(bullets ? '• $line' : line, style: textStyle),
        ],
      ),
    );
  }
}

class CoachBriefScreen extends StatelessWidget {
  const CoachBriefScreen({
    required this.launcher,
    required this.data,
    super.key,
  });

  final MatchHubLauncher launcher;
  final MatchHubData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${data.match.displayName} brief')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: launcher.changes,
          builder: (context, _) {
            final fresh = launcher.dataFor(data.match);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: CoachBriefView(
                    data: fresh,
                    brief: launcher.briefFor(fresh.match),
                    forecasts: launcher.eventController.forecastsFor(
                      fresh.match.key,
                    ),
                    onOpenTeam: (team) => launcher.openTeam(context, team),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
