import 'dart:async';

import 'package:flutter/material.dart';

import '../models/draft_board.dart';
import '../models/pick_layout.dart';
import '../models/pick_list.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/draft_controller.dart';
import '../state/event_controller.dart';
import '../state/event_stats_controller.dart';
import '../state/pick_list_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/glass_modal.dart';
import '../widgets/glass_popup_menu.dart';
import '../widgets/segment_label.dart';
import 'glass_chrome.dart';
import 'picks/draft_board_view.dart';
import 'picks/pick_facts.dart';
import 'picks/pick_list_view.dart';
import 'picks/prompt_dialog.dart';

enum _PicksView { list, draft }

class PicksTab extends StatefulWidget {
  const PicksTab({
    required this.pickListController,
    required this.eventController,
    required this.scoutingController,
    required this.configController,
    required this.onOpenTeam,
    this.eventStatsController,
    this.pitScoutingController,
    this.pitScoutConfigController,
    this.draftController,
    super.key,
  });

  final PickListController pickListController;
  final EventController eventController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final ValueChanged<int> onOpenTeam;
  final EventStatsController? eventStatsController;
  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  final DraftController? draftController;

  @override
  State<PicksTab> createState() => _PicksTabState();
}

class _PicksTabState extends State<PicksTab> {
  late final DraftController _draft =
      widget.draftController ?? DraftController();
  _PicksView _view = _PicksView.list;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    widget.eventController.addListener(_loadDraft);
    _loadDraft();
  }

  @override
  void dispose() {
    widget.eventController.removeListener(_loadDraft);
    if (widget.draftController == null) _draft.dispose();
    super.dispose();
  }

  void _loadDraft() => unawaited(_draft.load(widget.eventController.eventKey));

  Listenable get _listenable => Listenable.merge(<Listenable?>[
    widget.pickListController,
    widget.eventController,
    widget.scoutingController,
    widget.configController,
    widget.eventStatsController,
    widget.pitScoutingController,
    widget.pitScoutConfigController,
    _draft,
  ]);

  PickList? _selected(List<PickList> lists) {
    if (lists.isEmpty) return null;
    for (final list in lists) {
      if (list.id == _selectedId) return list;
    }
    return lists.first;
  }

  Future<void> _save(PickList list, PickLayout layout) async {
    final controller = widget.pickListController;
    await controller.saveLayout(list.id, layout.tiers, layout.dnp);
    final error = controller.lastError;
    if (error == null || !mounted) return;
    controller.clearLastError();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _newList() async {
    final name = await showPrompt(
      context,
      title: 'New pick list',
      label: 'Name',
      confirmLabel: 'Create',
      initial: 'Pick list',
      validate: (t) => t.isEmpty ? 'Give the list a name.' : null,
    );
    if (name == null) return;
    final created = await widget.pickListController.create(name);
    if (!mounted) return;
    if (created == null) {
      final error = widget.pickListController.lastError ?? 'Could not create.';
      widget.pickListController.clearLastError();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _selectedId = created.id);
  }

  Future<void> _renameList(PickList list) async {
    final name = await showPrompt(
      context,
      title: 'Rename list',
      label: 'Name',
      confirmLabel: 'Save',
      initial: list.name,
      validate: (t) => t.isEmpty ? 'Give the list a name.' : null,
    );
    if (name != null) await widget.pickListController.rename(list.id, name);
  }

  Future<void> _deleteList(PickList list) async {
    final ok = await showGlassConfirmDialog<bool>(
      context: context,
      title: 'Delete "${list.name}"?',
      content: const Text('Everyone on the team loses this list.'),
      actionsBuilder: (dialog) => [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (ok != true) return;
    await widget.pickListController.delete(list.id);
    if (mounted) setState(() => _selectedId = null);
  }

  Future<void> _resetDraft() async {
    final previous = _draft.actions;
    final messenger = ScaffoldMessenger.of(context);
    await _draft.reset();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Draft reset'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_draft.restore(previous)),
        ),
      ),
    );
  }

  PickFacts _facts() => PickFacts(
    eventController: widget.eventController,
    scoutingController: widget.scoutingController,
    configController: widget.configController,
    statsController: widget.eventStatsController,
    pitScoutingController: widget.pitScoutingController,
    pitScoutConfigController: widget.pitScoutConfigController,
  );

  @override
  Widget build(BuildContext context) {
    final bottom = 16 + GlassChrome.bottomInsetOf(context);
    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        final facts = _facts();
        final board = DraftBoard.replay(
          _draft.actions,
          facts.ranking,
          rounds: _draft.rounds,
        );
        final lists = widget.pickListController.lists;
        final selected = _selected(lists);
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<_PicksView>(
                        segments: const [
                          ButtonSegment(
                            value: _PicksView.list,
                            label: SegmentLabel('Pick list'),
                          ),
                          ButtonSegment(
                            value: _PicksView.draft,
                            label: SegmentLabel('Draft board'),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (s) =>
                            setState(() => _view = s.first),
                        showSelectedIcon: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_view == _PicksView.list)
                      ..._listSection(lists, selected, facts, board)
                    else
                      _draftSection(facts, board, selected),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _listSection(
    List<PickList> lists,
    PickList? selected,
    PickFacts facts,
    DraftBoard board,
  ) {
    if (!widget.pickListController.isReady) {
      return const [Center(child: CircularProgressIndicator())];
    }
    if (selected == null) {
      return [
        _Empty(
          message: 'No pick lists yet.',
          action: FilledButton(
            onPressed: _newList,
            child: const Text('Create a pick list'),
          ),
        ),
      ];
    }
    return [
      Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final list in lists)
                  ChoiceChip(
                    label: Text(list.name),
                    selected: list.id == selected.id,
                    onSelected: (_) => setState(() => _selectedId = list.id),
                  ),
                TextButton.icon(
                  onPressed: _newList,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New list'),
                ),
              ],
            ),
          ),
          GlassPopupMenuButton<String>(
            tooltip: 'List options',
            onSelected: (value) => value == 'rename'
                ? _renameList(selected)
                : _deleteList(selected),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename list')),
              PopupMenuItem(value: 'delete', child: Text('Delete list')),
            ],
          ),
        ],
      ),
      const SizedBox(height: 8),
      PickListView(
        layout: PickLayout.of(selected),
        facts: facts,
        picked: _takenLabels(board),
        onOpenTeam: widget.onOpenTeam,
        onChanged: (layout) => unawaited(_save(selected, layout)),
      ),
    ];
  }

  Map<int, String> _takenLabels(DraftBoard board) => <int, String>{
    for (var i = 0; i < board.alliances.length; i++) ...{
      board.alliances[i].captain: 'Captain of alliance ${i + 1}',
      for (final team in board.alliances[i].picks)
        team: 'Picked by alliance ${i + 1}',
    },
  };

  Widget _draftSection(PickFacts facts, DraftBoard board, PickList? selected) {
    if (board.alliances.isEmpty) {
      return const _Empty(
        message:
            'No teams are loaded for this event yet.\n'
            'Pick your event in Settings to run the draft.',
      );
    }
    return DraftBoardView(
      board: board,
      facts: facts,
      layout: selected == null ? null : PickLayout.of(selected),
      ourTeam: widget.eventController.myTeamNumber,
      officialRanking: facts.officialRanking,
      canUndo: _draft.canUndo,
      onRoundsChanged: (rounds) => unawaited(_draft.setRounds(rounds)),
      onOpenTeam: widget.onOpenTeam,
      onAccept: (team) => unawaited(_draft.pick(team)),
      onDecline: (team) {
        unawaited(_draft.decline(team));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$team declined')));
      },
      onUndo: () => unawaited(_draft.undo()),
      onReset: () => unawaited(_resetDraft()),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = StrategyPalette.mutedTextOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: muted),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
