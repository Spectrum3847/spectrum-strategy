import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/prescout_config_controller.dart';
import '../scouting/state/prescouting_controller.dart';
import '../scouting/state/scout_assignment_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scout_shift_controller.dart';
import '../scouting/state/shift_trade_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../scouting/ui/scout_assignments_screen.dart';
import '../scouting/ui/scout_shift_screen.dart';
import '../services/assistant/assistant_service.dart';
import '../services/statbotics/team_history_service.dart';
import '../services/issue_report_service.dart';
import '../services/match_directory.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../services/tour_service.dart';
import '../services/team_avatar_service.dart';
import '../services/usage_rollup_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/event_controller.dart';
import '../state/event_sections_controller.dart';
import '../state/event_stats_controller.dart';
import '../state/pick_list_controller.dart';
import '../state/playoff_board_controller.dart';
import '../state/post_match_report_controller.dart';
import '../state/strategy_controller.dart';
import '../state/trait_table_controller.dart';
import '../state/trex_assignments_controller.dart';
import '../state/trex_team_list_controller.dart';
import '../state/trex_trait_report_controller.dart';
import '../state/theme_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import 'database_tab.dart';
import 'docs_viewer_screen.dart';
import 'pit_scouting_screen.dart';
import 'prematch_tab.dart';
import 'prescouting_screen.dart';
import 'schedule_tab.dart';
import 'scouting_tab.dart';
import 'settings_tab.dart';
import 'trex_screen.dart';
import 'usage_tab.dart';
import 'welcome_tour.dart';
import 'sign_in_screen.dart';
import 'strategy_tab.dart';
import 'user_management_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.strategyController,
    required this.scoutingController,
    required this.cycleLogController,
    required this.playoffBoardController,
    required this.configController,
    required this.authService,
    required this.themeController,
    required this.userRoleController,
    required this.eventController,
    required this.pitScoutConfigController,
    required this.pitScoutingController,
    required this.prescoutConfigController,
    required this.prescoutingController,
    required this.postMatchReportController,
    this.teamAvatarService,
    this.issueReportService,
    this.pickListController,
    this.eventStatsController,
    this.eventSectionsController,
    this.assignmentController,
    this.shiftController,
    this.shiftTradeController,
    this.tourService,
    this.telemetryService,
    this.usageRollupService,
    this.traitTableController,
    this.trexAssignmentsController,
    this.trexTeamListController,
    this.trexTraitReportController,
    this.assistant,
    this.teamHistory,
    this.matchDirectory,
    super.key,
  });

  final StrategyController strategyController;
  final ScoutingController scoutingController;
  final CycleLogController cycleLogController;
  final PlayoffBoardController playoffBoardController;
  final ScoutConfigController configController;
  final SpectrumAuthService authService;
  final ThemeController themeController;
  final UserRoleController userRoleController;
  final EventController eventController;
  final PitScoutConfigController pitScoutConfigController;
  final PitScoutingController pitScoutingController;

  final PrescoutConfigController prescoutConfigController;
  final PrescoutingController prescoutingController;
  final PostMatchReportController postMatchReportController;
  final TeamAvatarService? teamAvatarService;
  final IssueReportService? issueReportService;
  final PickListController? pickListController;

  final EventStatsController? eventStatsController;
  final EventSectionsController? eventSectionsController;
  final ScoutAssignmentController? assignmentController;
  final ScoutShiftController? shiftController;
  final ShiftTradeController? shiftTradeController;
  final TourService? tourService;
  final TelemetryService? telemetryService;

  final UsageRollupService? usageRollupService;

  final TraitTableController? traitTableController;

  final TRexAssignmentsController? trexAssignmentsController;

  final TRexTeamListController? trexTeamListController;

  final TrexTraitReportController? trexTraitReportController;

  final AssistantService? assistant;

  final TeamHistoryService? teamHistory;

  final MatchDirectory? matchDirectory;

  @override
  State<AppShell> createState() => _AppShellState();
}

const _kTabMeta = [
  (
    label: 'Strategy',
    icon: Icons.draw_outlined,
    selectedIcon: Icons.draw_rounded,
  ),
  (
    label: 'Scout',
    icon: Icons.assignment_outlined,
    selectedIcon: Icons.assignment_rounded,
  ),
  (
    label: 'Prematch',
    icon: Icons.flag_outlined,
    selectedIcon: Icons.flag_rounded,
  ),
  (
    label: 'Database',
    icon: Icons.table_chart_outlined,
    selectedIcon: Icons.table_chart_rounded,
  ),
  (
    label: 'Docs',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book_rounded,
  ),
  (
    label: 'Users',
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts_rounded,
  ),
  (
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
  (
    label: 'Schedule',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month_rounded,
  ),
  (
    label: 'Usage',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
];

const _kOverflowOrder = [4, 7, 5, 8, 6];

class _AppShellState extends State<AppShell> {
  int _index = 0;

  int _lastPrimaryIndex = 0;

  final GlobalKey<StrategyTabState> _strategyKey =
      GlobalKey<StrategyTabState>();

  final GlobalKey _navBarKey = GlobalKey();

  final GlobalKey<PopupMenuButtonState<int>> _overflowMenuKey =
      GlobalKey<PopupMenuButtonState<int>>();

  bool _tourVisible = false;
  bool _tourCheckPending = false;

  @override
  void initState() {
    super.initState();
    widget.userRoleController.addListener(_onRoleChanged);
    _clampIndices();
    _maybeShowTour();
  }

  @override
  void dispose() {
    widget.userRoleController.removeListener(_onRoleChanged);
    super.dispose();
  }

  List<int> get _visibleTabIndices =>
      widget.userRoleController.visibleTabIndices;

  List<int> get _primaryTabIndices =>
      widget.userRoleController.primaryTabIndices;

  List<int> get _secondaryTabIndices =>
      widget.userRoleController.secondaryTabIndices;

  List<int> _orderedSecondaryTabs() {
    final secondary = _secondaryTabIndices;
    return [
      ..._kOverflowOrder.where(secondary.contains),
      ...secondary.where((i) => !_kOverflowOrder.contains(i)),
    ];
  }

  List<TourMenuItem> _secondaryTourMenuItems() => [
    for (final i in _orderedSecondaryTabs())
      (tabIndex: i, icon: _kTabMeta[i].icon, label: _kTabMeta[i].label),
  ];

  void _clampIndices() {
    final visible = _visibleTabIndices;
    final primary = _primaryTabIndices;
    if (visible.isNotEmpty && !visible.contains(_index)) {
      _index = primary.isNotEmpty ? primary.first : visible.first;
    }
    if (!primary.contains(_lastPrimaryIndex)) {
      _lastPrimaryIndex = primary.isNotEmpty ? primary.first : _index;
    }
  }

  int get _navIndex {
    final primary = _primaryTabIndices;
    final i = primary.indexOf(_lastPrimaryIndex);
    return i < 0 ? 0 : i;
  }

  void _onNavSelected(int navIndex) {
    final fullIndex = _primaryTabIndices[navIndex];
    if (fullIndex == _index) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _index = fullIndex;
      _lastPrimaryIndex = fullIndex;
    });

    final telemetry = widget.telemetryService;
    if (telemetry != null) {
      unawaited(
        telemetry.logEvent('tab_open', detail: _kTabMeta[fullIndex].label),
      );
    }
  }

  void _onSecondarySelected(int fullIndex) {
    if (fullIndex == _index) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _index = fullIndex);
  }

  void _onRoleChanged() {
    _clampIndices();
    setState(() {});
    _maybeShowTour();
  }

  Future<void> _openPitScouting() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PitScoutingScreen(
          controller: widget.pitScoutingController,
          configController: widget.pitScoutConfigController,
        ),
      ),
    );
  }

  Future<void> _openTrex() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TrexScreen(
          trexController: widget.trexAssignmentsController,
          trexTeamListController: widget.trexTeamListController,
          trexTraitReportController: widget.trexTraitReportController,
          canEditTRexAssignments:
              widget.userRoleController.roles.canEditTRexAssignments,
        ),
      ),
    );
  }

  Future<void> _openPrescouting() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PrescoutingScreen(
          controller: widget.prescoutingController,
          configController: widget.prescoutConfigController,
          assistant: widget.assistant,
        ),
      ),
    );
  }

  Future<void> _openScoutAssignments() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScoutAssignmentsScreen(
          eventController: widget.eventController,
          userRoleController: widget.userRoleController,
          controller: widget.assignmentController,
        ),
      ),
    );
  }

  Future<void> _openScoutShifts() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScoutShiftScreen(
          eventController: widget.eventController,
          userRoleController: widget.userRoleController,
          controller: widget.shiftController,
          tradeController: widget.shiftTradeController,
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    final actions = <Widget>[];
    if (_index == 0) {
      actions
        ..add(
          IconButton(
            onPressed: () => _strategyKey.currentState?.openMatchPicker(),
            tooltip: 'Matches',
            icon: const Icon(Icons.folder_open_rounded),
          ),
        )
        ..add(
          IconButton(
            onPressed: () => _strategyKey.currentState?.saveBoard(),
            tooltip: 'Save image',
            icon: const Icon(Icons.save_alt_rounded),
          ),
        )
        ..add(
          IconButton(
            onPressed: () => _strategyKey.currentState?.shareBoard(),
            tooltip: 'Share image',
            icon: const Icon(Icons.ios_share_rounded),
          ),
        );
    }
    if (_index == 1) {
      actions
        ..add(
          IconButton(
            onPressed: _openScoutAssignments,
            tooltip: 'Scout assignments',
            icon: const Icon(Icons.event_note_outlined),
          ),
        )
        ..add(
          IconButton(
            onPressed: _openScoutShifts,
            tooltip: 'Scout shifts',
            icon: const Icon(Icons.schedule_outlined),
          ),
        )
        ..add(
          Flexible(
            child: TextButton.icon(
              onPressed: _openPrescouting,
              icon: const Icon(Icons.person_search_outlined),
              label: const Text(
                'Pre-Scouting',
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: IconTheme.of(context).color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
                ),
              ),
            ),
          ),
        )
        ..add(
          IconButton(
            onPressed: _openPitScouting,
            tooltip: 'Pit scouting',
            icon: const Icon(Icons.handyman_outlined),
          ),
        );

      if (widget.trexAssignmentsController != null ||
          widget.trexTraitReportController != null) {
        actions.add(
          IconButton(
            onPressed: _openTrex,
            tooltip: 'T-Rex',
            icon: const Icon(Icons.pets_outlined),
          ),
        );
      }
    }
    final orderedSecondary = _orderedSecondaryTabs();
    if (orderedSecondary.isNotEmpty) {
      actions.add(
        _OverflowMenu(
          menuKey: _overflowMenuKey,
          items: orderedSecondary,
          activeIndex: _index,
          onSelected: _onSecondarySelected,
        ),
      );
    }
    actions.add(
      IconButton(
        onPressed: _openSignIn,
        tooltip: 'Account',
        icon: const Icon(Icons.account_circle_outlined),
      ),
    );
    return actions;
  }

  Future<void> _openSignIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SignInScreen(
          authService: widget.authService,
          scoutingController: widget.scoutingController,
          userRoleController: widget.userRoleController,
        ),
      ),
    );
  }

  List<NavigationDestination> _buildDestinations() {
    return _primaryTabIndices.map((i) {
      final m = _kTabMeta[i];
      return NavigationDestination(
        icon: Icon(m.icon),
        selectedIcon: Icon(m.selectedIcon),
        label: m.label,
      );
    }).toList();
  }

  Widget _buildTitle(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: StrategyPalette.primary,
            shape: BoxShape.rectangle,
          ),
        ),
        const SizedBox(width: 8),

        Flexible(
          child: Text(
            'Spectrum Strategy',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }

  Future<void> _maybeShowTour() async {
    final tour = widget.tourService;
    if (tour == null || _tourVisible || _tourCheckPending) return;
    if (_visibleTabIndices.isEmpty) return;
    _tourCheckPending = true;
    try {
      final seen = await tour.isSeen();
      if (!mounted || seen || _visibleTabIndices.isEmpty) return;
      setState(() => _tourVisible = true);
    } finally {
      _tourCheckPending = false;
    }
  }

  void _dismissTour() {
    setState(() => _tourVisible = false);

    widget.tourService?.markSeen();
  }

  void _replayTour() {
    if (_visibleTabIndices.isEmpty) return;

    final primary = _primaryTabIndices;
    setState(() {
      if (primary.isNotEmpty) {
        _index = primary.first;
        _lastPrimaryIndex = primary.first;
      }
      _tourVisible = true;
    });
  }

  void _onTourStepChanged(TourStep step) {
    final tabIndex = step.tabIndex;
    if (tabIndex == null || tabIndex == _index) return;
    if (_primaryTabIndices.contains(tabIndex)) {
      setState(() {
        _index = tabIndex;
        _lastPrimaryIndex = tabIndex;
      });
    } else if (_secondaryTabIndices.contains(tabIndex)) {
      setState(() => _index = tabIndex);
    }
  }

  ({String title, String message}) _noAccessCopy() {
    final snapshot = widget.authService.snapshot;
    final user = snapshot.user;
    if (user == null) {
      if (snapshot.state == SpectrumAuthState.error && snapshot.error != null) {
        return (
          title: 'Sign-in is unavailable on this device.',
          message: snapshot.error!,
        );
      }
      return (
        title: 'You are signed out.',
        message: 'Sign in with the Google account you use for the team.',
      );
    }
    final account = (user.email?.isNotEmpty ?? false)
        ? user.email!
        : user.displayName;

    const noAccess =
        'This account has no roles assigned, so it has no access. Ask an '
        'admin to set your roles from the Users tab.';
    return (
      title: 'No access',
      message: account.isEmpty
          ? noAccess
          : 'You are signed in as $account. $noAccess',
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTabIndices;

    if (visible.isEmpty && widget.userRoleController.isResolvingAuth) {
      return Scaffold(
        appBar: AppBar(titleSpacing: 0, title: _buildTitle(context)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (visible.isEmpty) {
      final copy = _noAccessCopy();
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _buildTitle(context),
          actions: [
            IconButton(
              onPressed: _openSignIn,
              tooltip: 'Account',
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    copy.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copy.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  if (widget.authService.currentUser == null)
                    FilledButton.icon(
                      onPressed: _openSignIn,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Sign in with Google'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _openSignIn,
                      icon: const Icon(Icons.switch_account_outlined),
                      label: const Text('Switch account'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final tabs = <Widget>[
      StrategyTab(
        key: _strategyKey,
        controller: widget.strategyController,
        eventController: widget.eventController,
        teamAvatarService: widget.teamAvatarService,
      ),
      ScoutingTab(
        strategyController: widget.strategyController,
        scoutingController: widget.scoutingController,
        configController: widget.configController,
        eventController: widget.eventController,
      ),
      PrematchTab(
        eventController: widget.eventController,
        scoutingController: widget.scoutingController,
        cycleLogController: widget.cycleLogController,
        playoffBoardController: widget.playoffBoardController,
        configController: widget.configController,
        pickListController: widget.pickListController,
        eventStatsController: widget.eventStatsController,
        eventSectionsController: widget.eventSectionsController,
        traitTableController: widget.traitTableController,
        canEditTraitTable: widget.userRoleController.roles.canEditTraitTable,
        assistant: widget.assistant,
        postMatchReportController: widget.postMatchReportController,
        userRoleController: widget.userRoleController,
        matchDirectory: widget.matchDirectory,
        pitScoutingController: widget.pitScoutingController,
        pitScoutConfigController: widget.pitScoutConfigController,
      ),
      DatabaseTab(
        scoutingController: widget.scoutingController,
        eventController: widget.eventController,
        cycleLogController: widget.cycleLogController,
        configController: widget.configController,
        canEditAnyEntry: widget.userRoleController.roles.canEditAnyEntry,
        canAddManualEntry: widget.userRoleController.roles.isMember,
        currentUserUid: widget.authService.currentUser?.uid,
        assistant: widget.assistant,
        teamHistory: widget.teamHistory,
        canPublishSummaries:
            widget.userRoleController.roles.canPublishSummaries,
        pitScoutingController: widget.pitScoutingController,
        pitScoutConfigController: widget.pitScoutConfigController,
      ),
      DocsTab(roles: widget.userRoleController.roles),
      UserManagementBody(roleController: widget.userRoleController),
      SettingsTab(
        configController: widget.configController,
        themeController: widget.themeController,
        eventController: widget.eventController,
        userRoleController: widget.userRoleController,
        pitScoutConfigController: widget.pitScoutConfigController,
        authService: widget.authService,
        issueReportService: widget.issueReportService,
        telemetryService: widget.telemetryService,
        onReplayTour: widget.tourService != null ? _replayTour : null,
      ),
      ScheduleTab(
        eventController: widget.eventController,
        scoutingController: widget.scoutingController,
        configController: widget.configController,
        cycleLogController: widget.cycleLogController,
        userRoleController: widget.userRoleController,
        postMatchReportController: widget.postMatchReportController,
        assistant: widget.assistant,
      ),
      UsageTab(
        service: widget.usageRollupService ?? FirestoreUsageRollupService(),
      ),
    ];

    final primary = _primaryTabIndices;
    final navBar = primary.length >= 2
        ? NavigationBar(
            key: _navBarKey,
            selectedIndex: _navIndex,
            onDestinationSelected: _onNavSelected,
            destinations: _buildDestinations(),
          )
        : null;

    final nav = navBar == null
        ? null
        : (_index != _lastPrimaryIndex)
        ? NavigationBarTheme(
            data: NavigationBarThemeData(
              indicatorColor: Colors.transparent,
              iconTheme: WidgetStatePropertyAll(
                IconThemeData(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              labelTextStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            child: navBar,
          )
        : navBar;

    final showBack = nav == null && _index != _lastPrimaryIndex;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            leading: showBack
                ? IconButton(
                    icon: const BackButtonIcon(),
                    tooltip: 'Back',
                    onPressed: () {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      setState(() => _index = _lastPrimaryIndex);
                    },
                  )
                : null,
            title: _buildTitle(context),
            actions: _buildAppBarActions(),
          ),
          body: IndexedStack(index: _index, children: tabs),
          bottomNavigationBar: nav,
        ),
        if (_tourVisible)
          WelcomeTourOverlay(
            steps: buildTourSteps(visible),
            eventController: widget.eventController,
            navBarKey: _navBarKey,
            primaryTabIndices: _primaryTabIndices,
            overflowMenuKey: _overflowMenuKey,
            secondaryMenuItems: _secondaryTourMenuItems(),
            onDone: _dismissTour,
            onStepChanged: _onTourStepChanged,
          ),
      ],
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.items,
    required this.activeIndex,
    required this.onSelected,
    this.menuKey,
  });

  final List<int> items;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  final GlobalKey<PopupMenuButtonState<int>>? menuKey;

  @override
  Widget build(BuildContext context) {
    final isActive = items.contains(activeIndex);
    final color = isActive ? Theme.of(context).colorScheme.primary : null;
    return PopupMenuButton<int>(
      key: menuKey,
      tooltip: 'More',
      icon: Icon(Icons.more_vert, color: color),
      onSelected: onSelected,
      itemBuilder: (_) => items.map((i) {
        final m = _kTabMeta[i];
        final isSelected = i == activeIndex;
        return PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(
                isSelected ? m.selectedIcon : m.icon,
                size: 20,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                m.label,
                style: isSelected
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      )
                    : null,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
