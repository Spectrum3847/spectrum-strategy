import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../freshness_pill.dart';
import 'match_hub_brief_tab.dart';
import 'match_hub_launcher.dart';
import 'match_hub_match_tab.dart';
import 'match_hub_plan_tab.dart';

class MatchHubScreen extends StatelessWidget {
  const MatchHubScreen({
    required this.launcher,
    required this.match,
    super.key,
  });

  final MatchHubLauncher launcher;
  final StatboticsMatch match;

  @override
  Widget build(BuildContext context) {
    final hasBrief = launcher.briefController != null;
    return DefaultTabController(
      length: hasBrief ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(match.displayName),
          actions: <Widget>[
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

        body: AnimatedBuilder(
          animation: launcher.changes,
          builder: (context, _) {
            final data = launcher.dataFor(match);
            return TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                MatchHubMatchTab(launcher: launcher, data: data),
                MatchHubPlanTab(launcher: launcher, data: data),
                if (hasBrief) MatchHubBriefTab(launcher: launcher, data: data),
              ],
            );
          },
        ),
      ),
    );
  }
}
