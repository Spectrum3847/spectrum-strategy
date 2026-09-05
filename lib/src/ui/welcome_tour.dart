import 'package:flutter/material.dart';

import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import 'event_picker_dialog.dart';

class TourStep {
  const TourStep({
    required this.icon,
    required this.title,
    required this.body,
    this.showEventAction = false,
    this.tabIndex,
  });

  final IconData icon;
  final String title;
  final String body;

  final bool showEventAction;

  final int? tabIndex;
}

typedef TourMenuItem = ({int tabIndex, IconData icon, String label});

List<TourStep> buildTourSteps(List<int> visibleTabIndices) {
  return <TourStep>[
    const TourStep(
      icon: Icons.waving_hand_outlined,
      title: 'Welcome to Spectrum Strategy',
      body:
          'Match strategy, scouting, and prematch planning in one place. '
          'Start by selecting your event; it loads the team list, the '
          'match schedule, and EPA stats.',
      showEventAction: true,
    ),
    if (visibleTabIndices.contains(0))
      const TourStep(
        icon: Icons.draw_outlined,
        tabIndex: 0,
        title: 'Strategy',
        body:
            'Draw the plan for each match on the field, phase by phase: '
            'auton, teleop, endgame. Place robot markers, add notes, and '
            'share the board as an image.',
      ),
    if (visibleTabIndices.contains(1))
      const TourStep(
        icon: Icons.assignment_outlined,
        tabIndex: 1,
        title: 'Scout',
        body:
            'Record what each robot does, match by match. Entries save on '
            'the device first and sync to the team database when you are '
            'online; QR transfer covers the no-signal case.',
      ),
    if (visibleTabIndices.contains(2))
      const TourStep(
        icon: Icons.flag_outlined,
        tabIndex: 2,
        title: 'Prematch',
        body:
            'Walk up to the field prepared: event rankings, team analysis '
            'and comparisons, playoff ranking, film review, and shared '
            'pick lists.',
      ),
    if (visibleTabIndices.contains(3))
      const TourStep(
        icon: Icons.table_rows_outlined,
        tabIndex: 3,
        title: 'Database',
        body:
            'Every scouting entry from the team, filterable by team and '
            'match. It is read-only and stays in sync with the cloud.',
      ),
    if (visibleTabIndices.contains(7))
      const TourStep(
        icon: Icons.calendar_month_outlined,
        tabIndex: 7,
        title: 'Schedule',
        body:
            'The match schedule for your event, plus an index of every team '
            'attending. Search your own team number to see just the matches '
            'you play.',
      ),
    if (visibleTabIndices.contains(4))
      const TourStep(
        icon: Icons.menu_book_outlined,
        tabIndex: 4,
        title: 'Docs',
        body:
            'Guides tailored to your role live here: how to scout, run '
            'strategy, or administer the app. Open one any time you are '
            'unsure how something works.',
      ),
    if (visibleTabIndices.contains(5))
      const TourStep(
        icon: Icons.manage_accounts_outlined,
        tabIndex: 5,
        title: 'Users',
        body:
            'Set roles for new teammates. New accounts start as a scouter '
            'once they sign in, so check here to grant strategy or admin '
            'access.',
      ),
    if (visibleTabIndices.contains(6))
      const TourStep(
        icon: Icons.settings_outlined,
        tabIndex: 6,
        title: 'Settings',
        body:
            'The scout form, the event, and your account live here. You '
            'can replay this tour from Settings any time.',
      ),
  ];
}

class WelcomeTourOverlay extends StatefulWidget {
  const WelcomeTourOverlay({
    required this.steps,
    required this.eventController,
    required this.onDone,
    this.navBarKey,
    this.primaryTabIndices = const <int>[],
    this.overflowMenuKey,
    this.secondaryMenuItems = const <TourMenuItem>[],
    this.onStepChanged,
    super.key,
  });

  final List<TourStep> steps;
  final EventController eventController;

  final GlobalKey? navBarKey;

  final List<int> primaryTabIndices;

  final GlobalKey? overflowMenuKey;

  final List<TourMenuItem> secondaryMenuItems;

  final VoidCallback onDone;

  final ValueChanged<TourStep>? onStepChanged;

  @override
  State<WelcomeTourOverlay> createState() => _WelcomeTourOverlayState();
}

class _WelcomeTourOverlayState extends State<WelcomeTourOverlay> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyStepChanged());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _notifyStepChanged() {
    if (!mounted || _page < 0 || _page >= widget.steps.length) return;
    widget.onStepChanged?.call(widget.steps[_page]);
  }

  void _notifyStepChangedFor(int page) {
    if (page < 0 || page >= widget.steps.length) return;
    widget.onStepChanged?.call(widget.steps[page]);
  }

  int get _currentPage => _pageController.hasClients
      ? (_pageController.page ?? _page.toDouble()).round()
      : _page;

  void _next() {
    final currentPage = _currentPage;
    if (currentPage >= widget.steps.length - 1) {
      widget.onDone();
      return;
    }
    final target = currentPage + 1;

    _notifyStepChangedFor(target);
    if (MediaQuery.of(context).disableAnimations) {
      _pageController.jumpToPage(target);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    final currentPage = _currentPage;
    if (currentPage <= 0) return;
    final target = currentPage - 1;
    _notifyStepChangedFor(target);
    if (MediaQuery.of(context).disableAnimations) {
      _pageController.jumpToPage(target);
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _selectEvent() async {
    await showEventPicker(context, widget.eventController);
  }

  TourStep? get _currentStep =>
      (_page < 0 || _page >= widget.steps.length) ? null : widget.steps[_page];

  bool get _currentStepIsSecondary {
    final tabIndex = _currentStep?.tabIndex;
    return tabIndex != null &&
        widget.secondaryMenuItems.any((i) => i.tabIndex == tabIndex);
  }

  Rect? _overflowButtonRect() {
    final box = widget.overflowMenuKey?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? _targetRect() {
    final tabIndex = _currentStep?.tabIndex;
    if (tabIndex == null) return null;
    if (_currentStepIsSecondary) return _overflowButtonRect();
    final slot = widget.primaryTabIndices.indexOf(tabIndex);
    if (slot < 0) return null;
    final box = widget.navBarKey?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
    final navRect = box.localToGlobal(Offset.zero) & box.size;
    final n = widget.primaryTabIndices.length;
    if (n == 0) return null;
    final slice = navRect.width / n;
    final center = navRect.left + slice * (slot + 0.5);
    const halfWidth = 36.0;
    return Rect.fromLTWH(
      center - halfWidth,
      navRect.top + 4,
      halfWidth * 2,
      navRect.height - 8,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = _page >= widget.steps.length - 1;
    final target = _targetRect();

    final liftCardAbove = target != null && !_currentStepIsSecondary;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardBottomPad = liftCardAbove
        ? (screenHeight - target.top + 12.0)
        : 16.0;
    final mockMenu = _currentStepIsSecondary ? _overflowButtonRect() : null;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDone,
            child: CustomPaint(
              painter: _SpotlightPainter(
                scrim: colorScheme.scrim.withValues(alpha: 0.4),
                hole: target,
              ),
            ),
          ),
        ),
        if (mockMenu != null)
          _MockOverflowMenu(
            anchor: mockMenu,
            items: widget.secondaryMenuItems,
            activeTabIndex: _currentStep?.tabIndex,
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            bottom: !liftCardAbove,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, cardBottomPad),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: StrategyPalette.surfaceOf(context),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(StrategyPalette.radiusMd),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 180,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: widget.steps.length,
                            onPageChanged: (page) {
                              setState(() => _page = page);
                              _notifyStepChanged();
                            },
                            itemBuilder: (context, index) => _StepContent(
                              step: widget.steps[index],
                              eventController: widget.eventController,
                              onSelectEvent: _selectEvent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (var i = 0; i < widget.steps.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: i == _page ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: i == _page
                                        ? colorScheme.primary
                                        : StrategyPalette.borderOf(context),

                                    borderRadius: const BorderRadius.all(
                                      Radius.circular(StrategyPalette.radiusSm),
                                    ),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (_page > 0)
                              TextButton(
                                onPressed: _previous,
                                child: const Text('Back'),
                              ),
                            if (!isLast)
                              TextButton(
                                onPressed: widget.onDone,
                                child: const Text('Skip'),
                              ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _next,
                              child: Text(isLast ? 'Done' : 'Next'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({
    required this.step,
    required this.eventController,
    required this.onSelectEvent,
  });

  final TourStep step;
  final EventController eventController;
  final Future<void> Function() onSelectEvent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(step.icon, size: 22, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(step.title, style: textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Text(
            step.body,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (step.showEventAction)
          AnimatedBuilder(
            animation: eventController,
            builder: (context, _) {
              return OutlinedButton.icon(
                onPressed: onSelectEvent,
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: Text(
                  eventController.hasEvent
                      ? 'Event: ${eventController.eventName.isNotEmpty ? eventController.eventName : eventController.eventKey}'
                      : 'Select event',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MockOverflowMenu extends StatelessWidget {
  const _MockOverflowMenu({
    required this.anchor,
    required this.items,
    required this.activeTabIndex,
  });

  final Rect anchor;
  final List<TourMenuItem> items;
  final int? activeTabIndex;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    return Positioned(
      top: anchor.bottom + 4,
      right: (screenWidth - anchor.right).clamp(0.0, screenWidth),
      child: Material(
        elevation: 8,
        color: StrategyPalette.surfaceOf(context),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 20,
                        color: item.tabIndex == activeTabIndex
                            ? colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item.label,
                        style: item.tabIndex == activeTabIndex
                            ? textTheme.bodyMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              )
                            : textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.scrim, this.hole});

  final Color scrim;
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = scrim);
    final target = hole;
    if (target != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          target,
          const Radius.circular(StrategyPalette.radiusMd),
        ),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.scrim != scrim;
}
