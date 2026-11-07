import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../freshness_pill.dart';
import 'match_hub_brief_tab.dart';
import 'match_hub_launcher.dart';
import 'match_hub_match_tab.dart';
import 'match_hub_plan_tab.dart';

class MatchHubScreen extends StatefulWidget {
  const MatchHubScreen({
    required this.launcher,
    required this.match,
    super.key,
  });

  final MatchHubLauncher launcher;
  final StatboticsMatch match;

  @override
  State<MatchHubScreen> createState() => _MatchHubScreenState();
}

class _MatchHubScreenState extends State<MatchHubScreen> {
  late StatboticsMatch _match = widget.match;

  MatchHubLauncher get _launcher => widget.launcher;

  void _step(int step) {
    final next = _launcher.adjacentMatch(_match, step);
    if (next != null) setState(() => _match = next);
  }

  @override
  Widget build(BuildContext context) {
    final launcher = _launcher;
    final hasBrief = launcher.briefController != null;
    return DefaultTabController(
      length: hasBrief ? 3 : 2,
      child: AnimatedBuilder(
        animation: launcher.changes,
        builder: (context, _) {
          final data = launcher.dataFor(_match);
          final key = ValueKey<String>(_match.key);
          return Scaffold(
            appBar: AppBar(
              title: Text(_match.displayName),
              actions: <Widget>[
                IconButton(
                  onPressed: launcher.adjacentMatch(_match, -1) == null
                      ? null
                      : () => _step(-1),
                  tooltip: 'Previous match',
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  onPressed: launcher.adjacentMatch(_match, 1) == null
                      ? null
                      : () => _step(1),
                  tooltip: 'Next match',
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                FreshnessPill(
                  scoutingController: launcher.scoutingController,
                  eventController: launcher.eventController,
                  pitScoutingController: launcher.pitScoutingController,
                ),
              ],
              bottom: TabBar(
                tabs: <Widget>[
                  const Tab(text: 'Match'),
                  const Tab(text: 'Plan'),
                  if (hasBrief) const Tab(text: 'Brief'),
                ],
              ),
            ),

            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                MatchHubMatchTab(key: key, launcher: launcher, data: data),
                MatchHubPlanTab(key: key, launcher: launcher, data: data),
                if (hasBrief)
                  MatchHubBriefTab(key: key, launcher: launcher, data: data),
              ],
            ),
          );
        },
      ),
    );
  }
}
