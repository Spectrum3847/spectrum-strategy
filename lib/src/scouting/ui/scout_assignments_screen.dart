import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../models/user_role.dart';
import '../../services/local_only_services.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../../state/event_controller.dart';
import '../../state/user_role_controller.dart';
import '../../theme/strategy_palette.dart';
import '../models/scout_assignment.dart';
import '../state/scout_assignment_controller.dart';

class ScoutAssignmentsScreen extends StatefulWidget {
  const ScoutAssignmentsScreen({
    required this.eventController,
    required this.userRoleController,
    ScoutAssignmentController? controller,
    super.key,
  }) : injectedController = controller;

  final EventController eventController;
  final UserRoleController userRoleController;

  final ScoutAssignmentController? injectedController;

  @override
  State<ScoutAssignmentsScreen> createState() => _ScoutAssignmentsScreenState();
}

class _ScoutAssignmentsScreenState extends State<ScoutAssignmentsScreen> {
  late final ScoutAssignmentController _controller;
  bool _mineOnly = false;

  bool get _canAssign => widget.userRoleController.roles.canEditAnyEntry;
  String? get _uid => widget.userRoleController.currentUid;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.injectedController ??
        ScoutAssignmentController(
          syncService: LocalOnlyScoutAssignmentSyncService(),
        );
    _controller.start();
  }

  @override
  void dispose() {
    if (widget.injectedController == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  String _tbaStation(String station) {
    final prefix = station.startsWith('red') ? 'R' : 'B';
    return '$prefix${station.substring(station.length - 1)}';
  }

  Future<void> _pickScouter(StatboticsMatch match, String station) async {
    final existing = _controller
        .forMatch(match.key)
        .where((a) => a.station == station)
        .toList();
    final currentUid = existing.isNotEmpty ? existing.first.scouterUid : null;

    final action = await showModalBottomSheet<_AssignAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ScouterPicker(
        roleController: widget.userRoleController,
        currentScouterUid: currentUid,
      ),
    );
    if (action == null || !mounted) return;

    if (action.clear) {
      await _controller.unassign(match.key, station);
    } else if (action.profile != null) {
      await _controller.assign(
        matchKey: match.key,
        matchNumber: match.matchNumber,
        station: station,
        scouterUid: action.profile!.uid,
        scouterName: action.profile!.displayName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scout assignments'),
        actions: [
          Row(
            children: [
              const Text('Mine'),
              Switch(
                value: _mineOnly,
                onChanged: (v) => setState(() => _mineOnly = v),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([widget.eventController, _controller]),
        builder: (context, _) {
          if (!widget.eventController.hasMatches) {
            return const _Empty(
              message:
                  'Select an event with a match schedule to assign scouters.',
            );
          }
          final matches = widget.eventController.matches.toList(growable: false)
            ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));

          final visible = _mineOnly
              ? matches
                    .where(
                      (m) => _controller
                          .forMatch(m.key)
                          .any((a) => a.scouterUid == _uid),
                    )
                    .toList(growable: false)
              : matches;

          if (visible.isEmpty) {
            return const _Empty(message: 'No matches assigned to you yet.');
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: visible.length,
                itemBuilder: (context, i) =>
                    _MatchCard(match: visible[i], state: this),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.state});

  final StatboticsMatch match;
  final _ScoutAssignmentsScreenState state;

  @override
  Widget build(BuildContext context) {
    final assignments = {
      for (final a in state._controller.forMatch(match.key)) a.station: a,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              match.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final station in kAllianceStations)
              _StationRow(
                station: station,
                team: match.teamForStation(state._tbaStation(station)),
                assignment: assignments[station],
                isMine: assignments[station]?.scouterUid == state._uid,
                onTap: state._canAssign
                    ? () => state._pickScouter(match, station)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.team,
    required this.assignment,
    required this.isMine,
    required this.onTap,
  });

  final String station;
  final int? team;
  final ScoutAssignment? assignment;
  final bool isMine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isRed = station.startsWith('red');
    final color = isRed
        ? StrategyPalette.allianceRed
        : StrategyPalette.allianceBlue;
    final scouter = assignment?.scouterName ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(
        Radius.circular(StrategyPalette.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(
                  Radius.circular(StrategyPalette.radiusSm),
                ),
              ),
              child: Text(
                station.substring(station.length - 1),
                style: const TextStyle(
                  color: StrategyPalette.onAlliance,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Text(team != null ? team.toString() : '—'),
            ),
            Expanded(
              child: Text(
                scouter.isEmpty ? 'Unassigned' : scouter,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scouter.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                  fontWeight: isMine ? FontWeight.w700 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isMine)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.person_pin_circle_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            if (onTap != null) const Icon(Icons.edit_outlined, size: 16),
          ],
        ),
      ),
    );
  }
}

class _AssignAction {
  const _AssignAction({this.profile, this.clear = false});
  final UserProfile? profile;
  final bool clear;
}

class _ScouterPicker extends StatelessWidget {
  const _ScouterPicker({
    required this.roleController,
    required this.currentScouterUid,
  });

  final UserRoleController roleController;
  final String? currentScouterUid;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<UserProfile>>(
        stream: roleController.streamAllProfiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final profiles = (snapshot.data ?? const <UserProfile>[])
              .where((p) => p.roles.isMember)
              .toList(growable: false);
          return ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Assign a scouter'), dense: true),
              if (currentScouterUid != null)
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('Unassign'),
                  onTap: () =>
                      Navigator.of(context)
                          .pop(const _AssignAction(clear: true)),
                ),
              for (final p in profiles)
                ListTile(
                  leading: Icon(
                    p.uid == currentScouterUid
                        ? Icons.check_circle
                        : Icons.person_outline,
                  ),
                  title: Text(
                    p.displayName.isEmpty ? '(no name)' : p.displayName,
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_AssignAction(profile: p)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
