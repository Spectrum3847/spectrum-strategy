import 'package:flutter/material.dart';

import 'match_hub/match_hub_launcher.dart';

class TeamLink extends StatelessWidget {
  const TeamLink({required this.team, required this.child, super.key});

  final int team;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = MatchHubScope.teamOpener(context, team);
    if (open == null) return child;
    return Semantics(
      button: true,
      label: 'Open team $team',
      excludeSemantics: true,
      child: InkWell(
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: child,
          ),
        ),
      ),
    );
  }
}
