import 'package:flutter/material.dart';

import '../../models/match_brief.dart';
import '../../scouting/services/match_hub_stats.dart';
import '../../services/match_directory.dart' show MatchSummary;
import '../../state/strategy_controller.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/alliance_tag.dart';
import '../strategy_tab.dart';
import 'match_hub_launcher.dart';
import 'match_hub_widgets.dart';

Future<void> openBoardForMatch(
  StrategyController controller, {
  required String eventKey,
  required String eventName,
  required int matchNumber,
  required String alliance,
}) async {
  final current = controller.session;
  if (current.eventKey == eventKey && current.matchNumber == matchNumber) {
    return;
  }
  MatchSummary? latest;
  for (final summary in await controller.listMatches()) {
    final sameMatch =
        summary.eventKey == eventKey && summary.matchNumber == matchNumber;
    if (!sameMatch) continue;
    if (latest == null || summary.updatedAt.isAfter(latest.updatedAt)) {
      latest = summary;
    }
  }
  if (latest != null) return controller.openMatch(latest.id);

  final remote = controller.remoteBoards
      .where((b) => b.eventKey == eventKey && b.matchNumber == matchNumber)
      .firstOrNull;
  if (remote != null) return controller.openRemoteBoard(remote.id);

  await controller.createMatch(
    eventKey: eventKey,
    eventName: eventName.isEmpty ? null : eventName,
    matchNumber: matchNumber,
    alliance: alliance,
  );
}

class MatchHubPlanTab extends StatefulWidget {
  const MatchHubPlanTab({
    required this.launcher,
    required this.data,
    super.key,
  });

  final MatchHubLauncher launcher;
  final MatchHubData data;

  @override
  State<MatchHubPlanTab> createState() => _MatchHubPlanTabState();
}

class _MatchHubPlanTabState extends State<MatchHubPlanTab>
    with AutomaticKeepAliveClientMixin {
  Future<void>? _boardReady;

  @override
  bool get wantKeepAlive => true;

  bool get _showsBoard =>
      widget.launcher.canEdit && widget.data.match.isQualification;

  @override
  void initState() {
    super.initState();
    if (_showsBoard) {
      final events = widget.launcher.eventController;
      _boardReady = openBoardForMatch(
        widget.launcher.strategyController,
        eventKey: events.eventKey,
        eventName: events.eventName,
        matchNumber: widget.data.match.matchNumber,
        alliance: widget.data.ourAlliance ?? 'Red',
      );
    }
  }

  Widget _board() {
    final launcher = widget.launcher;
    return FutureBuilder<void>(
      future: _boardReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return StrategyTab(
          controller: launcher.strategyController,
          eventController: launcher.eventController,
          teamAvatarService: launcher.teamAvatarService,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final plans = RobotPlansCard(launcher: widget.launcher, data: widget.data);
    if (!_showsBoard) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (widget.launcher.canEdit) ...<Widget>[
                Text(
                  'Boards are kept per qualification match number, so a '
                  'playoff match has no board here. Draw playoff boards in '
                  'the Strategy tab.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
                ),
                const SizedBox(height: 12),
              ],
              plans,
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final panel = ListView(
          padding: const EdgeInsets.all(8),
          children: <Widget>[plans],
        );
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _board()),
              SizedBox(width: 380, child: panel),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(flex: 3, child: _board()),
            Expanded(flex: 2, child: panel),
          ],
        );
      },
    );
  }
}

class RobotPlansCard extends StatefulWidget {
  const RobotPlansCard({required this.launcher, required this.data, super.key});

  final MatchHubLauncher launcher;
  final MatchHubData data;

  @override
  State<RobotPlansCard> createState() => _RobotPlansCardState();
}

class _RobotPlansCardState extends State<RobotPlansCard> {
  final _fields = <int, TextEditingController>{};
  late MatchBrief _loaded;
  bool _dirty = false;
  bool _saving = false;

  MatchHubLauncher get _launcher => widget.launcher;

  @override
  void initState() {
    super.initState();
    _loaded = _launcher.briefFor(widget.data.match);
    for (final team in widget.data.preview.allTeams) {
      _fields.putIfAbsent(
        team.teamNumber,
        () => TextEditingController(text: _loaded.planFor(team.teamNumber)),
      );
    }
    _launcher.briefController?.addListener(_onBriefChanged);
  }

  @override
  void dispose() {
    _launcher.briefController?.removeListener(_onBriefChanged);
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _onBriefChanged() {
    if (!mounted) return;

    if (_dirty) return;
    final latest = _launcher.briefFor(widget.data.match);
    if (latest.updatedAt == _loaded.updatedAt) {
      setState(() {});
      return;
    }
    setState(() {
      _loaded = latest;
      for (final entry in _fields.entries) {
        entry.value.text = latest.planFor(entry.key);
      }
    });
  }

  Future<void> _save() async {
    final briefs = _launcher.briefController;
    if (briefs == null) return;
    setState(() => _saving = true);
    final saved = await briefs.save(
      eventKey: _launcher.eventController.eventKey,
      matchId: _launcher.matchIdOf(widget.data.match),
      robotPlans: <int, String>{
        for (final entry in _fields.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) {
        _dirty = false;
        _loaded = _launcher.briefFor(widget.data.match);
      }
    });
    if (saved) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Plans saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final briefs = _launcher.briefController;
    if (briefs == null) return const SizedBox.shrink();
    final canEdit = _launcher.canEdit;
    return HubSection(
      title: 'Robot plans',
      trailing: MatchBriefSyncChip(status: briefs.syncStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final team in widget.data.preview.allTeams)
            _PlanRow(
              team: team.teamNumber,
              nickname: team.nickname,
              isRed: team.isRed,
              controller: _fields[team.teamNumber]!,
              canEdit: canEdit,
              onChanged: () => setState(() => _dirty = true),
              onOpenTeam: () => _launcher.openTeam(context, team.teamNumber),
            ),
          if (briefs.failedWrites.hasFailures)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The last save could not be written to this device. Try again.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (canEdit) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _dirty && !_saving ? _save : null,
                child: const Text('Save plans'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.team,
    required this.nickname,
    required this.isRed,
    required this.controller,
    required this.canEdit,
    required this.onChanged,
    required this.onOpenTeam,
  });

  final int team;
  final String nickname;
  final bool isRed;
  final TextEditingController controller;
  final bool canEdit;
  final VoidCallback onChanged;
  final VoidCallback onOpenTeam;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plan = controller.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AllianceTag(alliance: isRed ? 'Red' : 'Blue', width: 44),
              const SizedBox(width: 8),
              Expanded(
                child: HubTeamLink(
                  team: team,
                  nickname: nickname,
                  onTap: onOpenTeam,
                  style: text.titleSmall,
                ),
              ),
            ],
          ),
          if (canEdit)
            TextField(
              controller: controller,
              maxLength: MatchBrief.maxPlanLength,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: 'Plan for $team'),
              onChanged: (_) => onChanged(),
            )
          else
            Text(
              plan.isEmpty ? 'No plan written' : plan,
              style: text.bodyMedium,
            ),
        ],
      ),
    );
  }
}
