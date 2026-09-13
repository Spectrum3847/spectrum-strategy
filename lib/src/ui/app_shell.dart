import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:liquid_glass/liquid_glass.dart';

import 'glass_chrome.dart';

import '../models/user_role.dart';
import '../scouting/services/accuracy_mapping_service.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/prescout_config_controller.dart';
import '../scouting/state/prescouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/pit_shift_mirror_controller.dart';
import '../scouting/state/scout_shift_controller.dart';
import '../scouting/state/shift_trade_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../scouting/ui/scout_shift_screen.dart';
import '../services/assistant/assistant_service.dart';
import '../services/statbotics/team_history_service.dart';
import '../state/assistant_chat_controller.dart';
import '../services/issue_report_service.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../services/tour_service.dart';
import '../services/team_avatar_service.dart';
import '../services/usage_rollup_service.dart';
import '../state/cycle_log_controller.dart';
import '../state/event_controller.dart';
import '../state/event_sections_controller.dart';
import '../state/event_stats_controller.dart';
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
import 'platform_target.dart';
import 'usage_tab.dart';
import 'welcome_tour.dart';
import 'sign_in_screen.dart';
import 'ai_tab.dart';
import 'strategy_tab.dart';
import 'user_management_screen.dart';
import '../widgets/glass_popup_menu.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.strategyController,
    required this.scoutingController,
    required this.cycleLogController,
    required this.playoffBoardController,
    required this.configController,
    required this.authService,
    required this.themeController,
    this.debugLiquidGlassSupported,
    required this.userRoleController,
    required this.eventController,
    required this.pitScoutConfigController,
    required this.pitScoutingController,
    required this.prescoutConfigController,
    required this.prescoutingController,
    required this.postMatchReportController,
    this.teamAvatarService,
    this.issueReportService,
    this.accuracyMappingService,
    this.eventStatsController,
    this.eventSectionsController,
    this.shiftController,
    this.shiftTradeController,
    this.pitShiftMirrorController,
    this.tourService,
    this.telemetryService,
    this.usageRollupService,
    this.traitTableController,
    this.trexAssignmentsController,
    this.trexTeamListController,
    this.trexTraitReportController,
    this.assistant,
    this.assistantChatController,
    this.teamHistory,
    super.key,
  });

  final StrategyController strategyController;
  final ScoutingController scoutingController;
  final CycleLogController cycleLogController;
  final PlayoffBoardController playoffBoardController;
  final ScoutConfigController configController;
  final SpectrumAuthService authService;
  final ThemeController themeController;

  @visibleForTesting
  final bool? debugLiquidGlassSupported;
  final UserRoleController userRoleController;
  final EventController eventController;
  final PitScoutConfigController pitScoutConfigController;
  final PitScoutingController pitScoutingController;

  final PrescoutConfigController prescoutConfigController;
  final PrescoutingController prescoutingController;
  final PostMatchReportController postMatchReportController;
  final TeamAvatarService? teamAvatarService;
  final IssueReportService? issueReportService;

  final AccuracyMappingService? accuracyMappingService;

  final EventStatsController? eventStatsController;
  final EventSectionsController? eventSectionsController;
  final ScoutShiftController? shiftController;
  final ShiftTradeController? shiftTradeController;
  final PitShiftMirrorController? pitShiftMirrorController;
  final TourService? tourService;
  final TelemetryService? telemetryService;

  final UsageRollupService? usageRollupService;

  final TraitTableController? traitTableController;

  final TRexAssignmentsController? trexAssignmentsController;

  final TRexTeamListController? trexTeamListController;

  final TrexTraitReportController? trexTraitReportController;

  final AssistantService? assistant;

  final AssistantChatController? assistantChatController;

  final TeamHistoryService? teamHistory;

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
  (
    label: 'AI',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
  ),
];

const _kSecondaryOrder = [4, 7, 9, 5, 8, 6];

const _kAiTabIndex = 9;

class _AppShellState extends State<AppShell> {
  int _index = 0;

  final GlobalKey<StrategyTabState> _strategyKey =
      GlobalKey<StrategyTabState>();

  final GlobalKey _tabMenuKey = GlobalKey();

  bool _tourVisible = false;
  bool _tourCheckPending = false;

  @override
  void initState() {
    super.initState();
    widget.userRoleController.addListener(_onRoleChanged);

    widget.themeController.addListener(_onThemeChanged);
    _clampIndices();
    _maybeShowTour();
    final override = widget.debugLiquidGlassSupported;
    if (override != null) {
      _glassSupported = override;
    } else {
      spectrumGlassSupported().then((value) {
        if (mounted) setState(() => _glassSupported = value);
      });
    }
  }

  bool _glassSupported = false;

  bool get _useGlass => _glassSupported && widget.themeController.liquidGlass;

  @override
  void dispose() {
    widget.userRoleController.removeListener(_onRoleChanged);
    widget.themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  List<int> get _visibleTabIndices => [
    for (final i in widget.userRoleController.visibleTabIndices)
      if (i != _kAiTabIndex || isLocalModelPlatform) i,
  ];

  List<int> get _primaryTabIndices =>
      widget.userRoleController.primaryTabIndices;

  List<int> get _secondaryTabIndices {
    final primary = _primaryTabIndices.toSet();
    return _visibleTabIndices.where((i) => !primary.contains(i)).toList();
  }

  List<int> _orderedTabs() {
    final secondary = _secondaryTabIndices;
    return [
      ..._primaryTabIndices,
      ..._kSecondaryOrder.where(secondary.contains),
      ...secondary.where((i) => !_kSecondaryOrder.contains(i)),
    ];
  }

  List<TourMenuItem> _tourMenuItems() => [
    for (final i in _orderedTabs())
      (tabIndex: i, icon: _kTabMeta[i].icon, label: _kTabMeta[i].label),
  ];

  void _clampIndices() {
    final visible = _visibleTabIndices;
    final primary = _primaryTabIndices;
    if (visible.isNotEmpty && !visible.contains(_index)) {
      _index = primary.isNotEmpty ? primary.first : visible.first;
    }
  }

  void _onTabSelected(int fullIndex) {
    if (fullIndex == _index) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _index = fullIndex);

    final telemetry = widget.telemetryService;
    if (telemetry != null) {
      unawaited(
        telemetry.logEvent('tab_open', detail: _kTabMeta[fullIndex].label),
      );
    }
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
          canEditAnyEntry: widget.userRoleController.roles.canEditAnyEntry,
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
          canEditAnyEntry: widget.userRoleController.roles.canEditAnyEntry,
          eventKey: widget.eventController.eventKey,
          eventController: widget.eventController,
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
          canEditAnyEntry: widget.userRoleController.roles.canEditAnyEntry,
          assistant: widget.assistant,
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
          pitMirrorController: widget.pitShiftMirrorController,
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
      if (primary.isNotEmpty) _index = primary.first;
      _tourVisible = true;
    });
  }

  void _onTourStepChanged(TourStep step) {
    final tabIndex = step.tabIndex;
    if (tabIndex == null || tabIndex == _index) return;
    if (!_visibleTabIndices.contains(tabIndex)) return;
    setState(() => _index = tabIndex);
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
        eventStatsController: widget.eventStatsController,
        eventSectionsController: widget.eventSectionsController,
        assistant: widget.assistant,
        postMatchReportController: widget.postMatchReportController,
        userRoleController: widget.userRoleController,
        pitScoutingController: widget.pitScoutingController,
        pitScoutConfigController: widget.pitScoutConfigController,
        teamHistory: widget.teamHistory,
        trexTraitReportController: widget.trexTraitReportController,
      ),
      DatabaseTab(
        scoutingController: widget.scoutingController,
        eventController: widget.eventController,
        configController: widget.configController,
        canEditAnyEntry: widget.userRoleController.roles.canEditAnyEntry,
        currentUserUid: widget.authService.currentUser?.uid,
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
        accuracyMappingService: widget.accuracyMappingService,
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
      AiTab(
        chatController: widget.assistantChatController,
        applies: isLocalModelPlatform,
        hasLlamaRuntime: isDesktopPlatform,
        hasMcp: isLocalModelPlatform,
      ),
    ];

    final glass = _useGlass;

    final orderedTabs = _orderedTabs();

    final appBar = AppBar(
      titleSpacing: 0,
      backgroundColor: glass ? Colors.transparent : null,
      elevation: glass ? 0 : null,
      scrolledUnderElevation: glass ? 0 : null,
      leading: orderedTabs.length >= 2
          ? _TabMenu(
              menuKey: _tabMenuKey,
              items: orderedTabs,
              activeIndex: _index,
              onSelected: _onTabSelected,
            )
          : null,
      title: _buildTitle(context),
      actions: _buildAppBarActions(),
    );

    return GlassChrome(
      enabled: glass,
      child: Stack(
        children: [
          Scaffold(
            appBar: glass
                ? _GlassBar(
                    brightness: Theme.of(context).brightness,
                    child: appBar,
                  )
                : appBar,
            body: IndexedStack(index: _index, children: tabs),
          ),
          if (_tourVisible)
            WelcomeTourOverlay(
              steps: buildTourSteps(visible),
              eventController: widget.eventController,
              menuKey: _tabMenuKey,
              menuItems: _tourMenuItems(),
              onDone: _dismissTour,
              onStepChanged: _onTourStepChanged,
            ),
        ],
      ),
    );
  }
}

class _TabMenu extends StatelessWidget {
  const _TabMenu({
    required this.items,
    required this.activeIndex,
    required this.onSelected,
    this.menuKey,
  });

  final List<int> items;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  final GlobalKey? menuKey;

  @override
  Widget build(BuildContext context) {
    return GlassPopupMenuButton<int>(
      key: menuKey,
      tooltip: 'Tabs',
      icon: const Icon(Icons.menu),
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

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.brightness, required this.child});

  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: LiquidGlass(
            key: ValueKey(brightness),
            cornerRadius: 0,
            brightness: brightness,
          ),
        ),
        child,
      ],
    );
  }
}

class _GlassBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassBar({required this.brightness, required this.child});

  final Brightness brightness;
  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) =>
      _GlassSurface(brightness: brightness, child: child);
}
