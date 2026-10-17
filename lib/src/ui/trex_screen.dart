import 'package:flutter/material.dart';

import '../state/event_controller.dart';
import '../state/trex_assignments_controller.dart';
import '../state/trex_team_list_controller.dart';
import '../state/trex_trait_report_controller.dart';
import 'tab_swipe.dart';
import 'trex_assignments_view.dart';
import 'trex_database_screen.dart';
import 'trex_traits_screen.dart';

class TrexScreen extends StatelessWidget {
  const TrexScreen({
    this.trexController,
    this.trexTeamListController,
    this.trexTraitReportController,
    this.canEditTRexAssignments = false,
    this.canEditAnyEntry = false,
    this.eventKey = '',
    this.eventController,
    super.key,
  });

  final TRexAssignmentsController? trexController;

  final TRexTeamListController? trexTeamListController;

  final TrexTraitReportController? trexTraitReportController;

  final bool canEditTRexAssignments;

  final bool canEditAnyEntry;

  final String eventKey;

  final EventController? eventController;

  @override
  Widget build(BuildContext context) {
    final trex = trexController;
    final trexTraits = trexTraitReportController;

    final tabs = <Tab>[
      if (trex != null) const Tab(text: 'Assignments'),
      if (trexTraits != null) const Tab(text: 'Traits'),
      if (trexTraits != null) const Tab(text: 'Database'),
    ];
    final tabViews = <Widget>[
      if (trex != null)
        TRexAssignmentsView(
          controller: trex,
          teamListController: trexTeamListController,
          canEdit: canEditTRexAssignments,
        ),
      if (trexTraits != null)
        TrexTraitsScreen(
          controller: trexTraits,
          canEditAnyEntry: canEditAnyEntry,
          eventKey: eventKey,
          eventController: eventController,
        ),
      if (trexTraits != null) TrexDatabaseScreen(controller: trexTraits),
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
        body: TabBarView(physics: tabSwipePhysics, children: tabViews),
      ),
    );
  }
}
