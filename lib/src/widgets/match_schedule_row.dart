import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../theme/strategy_palette.dart';

const kMatchCompLevelOrder = <String>['qm', 'ef', 'qf', 'sf', 'f'];

List<StatboticsMatch> sortMatchesByCompLevel(List<StatboticsMatch> matches) {
  int rank(String level) {
    final index = kMatchCompLevelOrder.indexOf(level);
    return index < 0 ? kMatchCompLevelOrder.length : index;
  }

  return matches.toList()..sort((a, b) {
    final byLevel = rank(a.compLevel).compareTo(rank(b.compLevel));
    return byLevel != 0 ? byLevel : a.matchNumber.compareTo(b.matchNumber);
  });
}

class MatchScheduleRow extends StatelessWidget {
  const MatchScheduleRow({
    required this.match,
    required this.nicknames,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final StatboticsMatch match;

  final Map<int, String> nicknames;

  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      onTap: onTap,
      isThreeLine: true,
      title: Text(
        match.displayName,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AllianceLine(
              label: 'Red',
              color: StrategyPalette.allianceRed,
              teams: match.redTeams,
              nicknames: nicknames,
            ),
            const SizedBox(height: 4),
            _AllianceLine(
              label: 'Blue',
              color: StrategyPalette.allianceBlue,
              teams: match.blueTeams,
              nicknames: nicknames,
            ),
          ],
        ),
      ),
    );
  }
}

class _AllianceLine extends StatelessWidget {
  const _AllianceLine({
    required this.label,
    required this.color,
    required this.teams,
    required this.nicknames,
  });

  final String label;
  final Color color;
  final List<int> teams;
  final Map<int, String> nicknames;

  String _teamLabel(int team) {
    final nick = nicknames[team];
    if (nick == null || nick.isEmpty) return team.toString();
    return '$team $nick';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(
              Radius.circular(StrategyPalette.radiusSm),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: StrategyPalette.onAlliance,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            teams.isEmpty ? 'Teams not set' : teams.map(_teamLabel).join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
