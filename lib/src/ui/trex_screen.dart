import 'package:flutter/material.dart';

import '../state/trex_assignments_controller.dart';
import '../state/trex_team_list_controller.dart';
import '../state/trex_trait_report_controller.dart';
import 'trex_assignments_view.dart';
import 'trex_traits_screen.dart';

class TrexScreen extends StatelessWidget {
  const TrexScreen({
    this.trexController,
    this.trexTeamListController,
    this.trexTraitReportController,
    this.canEditTRexAssignments = false,
    super.key,
  });

  final TRexAssignmentsController? trexController;

  final TRexTeamListController? trexTeamListController;

  final TrexTraitReportController? trexTraitReportController;

  final bool canEditTRexAssignments;

  @override
  Widget build(BuildContext context) {
    final trex = trexController;
    final trexTraits = trexTraitReportController;

    final tabs = <Tab>[
      if (trex != null) const Tab(text: 'Assignments'),
      if (trexTraits != null) const Tab(text: 'Traits'),
    ];
    final tabViews = <Widget>[
      if (trex != null)
        TRexAssignmentsView(
          controller: trex,
          teamListController: trexTeamListController,
          canEdit: canEditTRexAssignments,
        ),
      if (trexTraits != null) TrexTraitsScreen(controller: trexTraits),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('T-Rex')),
        body: const Center(child: Text('No T-Rex data source is wired in.')),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('T-Rex'),
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        body: TabBarView(children: tabViews),
      ),
    );
  }
}
