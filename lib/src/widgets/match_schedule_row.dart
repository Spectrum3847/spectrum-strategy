import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'alliance_tag.dart';

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
            AllianceLine(
              label: 'Red',
              teams: match.redTeams,
              nicknames: nicknames,
            ),
            const SizedBox(height: 4),
            AllianceLine(
              label: 'Blue',
              teams: match.blueTeams,
              nicknames: nicknames,
            ),
          ],
        ),
      ),
    );
  }
}

class AllianceLine extends StatelessWidget {
  const AllianceLine({
    required this.label,
    required this.teams,
    required this.nicknames,
    this.highlightTeam,
    super.key,
  });

  final String label;
  final List<int> teams;
  final Map<int, String> nicknames;
  final int? highlightTeam;

  String _teamLabel(int team) {
    final nick = nicknames[team];
    if (nick == null || nick.isEmpty) return team.toString();
    return '$team $nick';
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AllianceTag(alliance: label, width: 44),
        const SizedBox(width: 8),
        Expanded(
          child: teams.isEmpty
              ? Text('Teams not set', style: style)
              : Text.rich(
                  TextSpan(
                    children: <TextSpan>[
                      for (var i = 0; i < teams.length; i++) ...[
                        if (i > 0) const TextSpan(text: ' · '),
                        TextSpan(
                          text: _teamLabel(teams[i]),
                          style: teams[i] == highlightTeam
                              ? TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                  style: style,
                ),
        ),
      ],
    );
  }
}
