import 'package:flutter/material.dart';

import '../models/strategy_session.dart';
import '../services/field_map_catalog.dart';
import '../services/match_directory.dart';
import '../services/strategy_board_sync_service.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../services/strategy_export_service.dart';
import '../services/team_avatar_service.dart';
import '../state/event_controller.dart';
import '../state/failed_write_tracker.dart';
import '../state/strategy_controller.dart';
import '../services/board_event_scope.dart';
import '../theme/strategy_palette.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/match_schedule_row.dart';
import '../widgets/strategy_field_canvas.dart';
import '../widgets/sync_status_pill.dart';

class StrategyTab extends StatefulWidget {
  const StrategyTab({
    required this.controller,
    required this.eventController,
    this.teamAvatarService,
    super.key,
  });

  final StrategyController controller;
  final EventController eventController;
  final TeamAvatarService? teamAvatarService;

  @override
  State<StrategyTab> createState() => StrategyTabState();
}

class StrategyTabState extends State<StrategyTab> {
  final GlobalKey _boardKey = GlobalKey();
  final StrategyExportService _exportService = StrategyExportService();
  late final TextEditingController _eventController;
  late final TextEditingController _matchController;
  late final TextEditingController _noteController;
  late final TextEditingController _teamImportController;
  late Future<FieldMapCatalogData> _fieldCatalogFuture;
  String? _statusMessage;
  StatboticsMatch? _selectedMatch;

  StrategyController get controller => widget.controller;
  EventController get eventController => widget.eventController;

  @override
  void initState() {
    super.initState();
    _eventController = TextEditingController(
      text: controller.session.eventName,
    );
    _matchController = TextEditingController(
      text: controller.session.matchNumber.toString(),
    );
    _noteController = TextEditingController(
      text: controller.session.noteFor(controller.session.selectedPhase),
    );
    _teamImportController = TextEditingController();
    _fieldCatalogFuture = FieldMapCatalog().load();
    controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    controller.removeListener(_syncFromController);
    _eventController.dispose();
    _matchController.dispose();
    _noteController.dispose();
    _teamImportController.dispose();
    super.dispose();
  }

  void _stepPhase(StrategyController controller, int delta) {
    const phases = StrategyPhase.values;
    final current = phases.indexOf(controller.session.selectedPhase);
    final next = (current + delta) % phases.length;
    controller.selectPhase(phases[next < 0 ? next + phases.length : next]);
  }

  void _reloadFieldCatalog() {
    setState(() => _fieldCatalogFuture = FieldMapCatalog().load());
  }

  Widget _fieldCatalogError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Field maps unavailable',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Retry loading field maps',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: _reloadFieldCatalog,
          ),
        ],
      ),
    );
  }

  void _syncFromController() {
    final session = controller.session;

    if (_eventController.text.trim() != session.eventName) {
      _eventController.value = _eventController.value.copyWith(
        text: session.eventName,
        selection: TextSelection.collapsed(offset: session.eventName.length),
        composing: TextRange.empty,
      );
    }
    final matchText = session.matchNumber.toString();
    if (_matchController.text != matchText) {
      _matchController.value = _matchController.value.copyWith(
        text: matchText,
        selection: TextSelection.collapsed(offset: matchText.length),
        composing: TextRange.empty,
      );
    }
    final noteText = session.noteFor(session.selectedPhase);
    if (_noteController.text != noteText) {
      _noteController.value = _noteController.value.copyWith(
        text: noteText,
        selection: TextSelection.collapsed(offset: noteText.length),
        composing: TextRange.empty,
      );
    }
  }

  Future<void> _importTeams() async {
    final importedCount = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: false,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Import team numbers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _teamImportController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Team numbers',
                  hintText: 'Paste team numbers separated by commas, spaces, or new lines',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        controller.loadTeamsFromText(
                          _teamImportController.text,
                        );
                        Navigator.of(context)
                            .pop(controller.session.teamNumbers.length);
                      },
                      child: const Text('Import'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || importedCount == null) return;
    setState(() {
      _statusMessage = 'Loaded $importedCount team numbers.';
    });
  }

  Future<void> openMatchPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,

      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _MatchPickerSheet(
          controller: controller,
          eventKey: eventController.eventKey,
          eventName: eventController.eventName,
        );
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> shareBoard() async {
    try {
      await _exportService.shareBoardImage(
        boundaryKey: _boardKey,
        session: controller.session,
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Shared ${controller.session.title}.';
      });
    } catch (e) {
      if (!mounted) return;
      _showExportSnack('Could not share the board: $e');
    }
  }

  Future<void> saveBoard() async {
    try {
      final result = await _exportService.exportBoardPng(
        boundaryKey: _boardKey,
        session: controller.session,
      );
      if (!mounted) return;
      final name = result.file.path.split(RegExp(r'[\\/]')).last;
      setState(() {
        _statusMessage = 'Saved $name.';
      });
      _showExportSnack(result.savedMessage);
    } catch (e) {
      if (!mounted) return;
      _showExportSnack('Could not save the image: $e');
    }
  }

  void _showExportSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _toolHint(StrategyTool tool) {
    switch (tool) {
      case StrategyTool.draw:
        return 'Draw: drag on the board to sketch a path.';
      case StrategyTool.robot:
        return 'Robot: tap the board to drop the selected team.';
      case StrategyTool.delete:
        return 'Erase: tap a single line or robot to remove just that one. '
            'Use Clear phase or Clear all to wipe everything.';
    }
  }

  void _showEraseUndo(StrategySession snapshot) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Element erased'),

          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => controller.restoreSnapshot(snapshot),
          ),
        ),
      );
  }

  void _clearWithUndo({required String message, required VoidCallback action}) {
    final snapshot = controller.captureSnapshot();
    action();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => controller.restoreSnapshot(snapshot),
          ),
        ),
      );
  }

  void _loadTeamsFromEvent() {
    if (!eventController.hasEvent) return;
    if (eventController.teamNumbers.isEmpty) return;
    controller.importTeams(eventController.teamNumbers);
    controller.setEventKey(eventController.eventKey);
    if (eventController.eventName.isNotEmpty) {
      controller.setEventName(eventController.eventName);
      _eventController.value = _eventController.value.copyWith(
        text: eventController.eventName,
        selection: TextSelection.collapsed(
          offset: eventController.eventName.length,
        ),
        composing: TextRange.empty,
      );
    }
    setState(() {
      _statusMessage =
          'Loaded ${eventController.teamNumbers.length} teams from '
          '${eventController.eventName.isNotEmpty ? eventController.eventName : eventController.eventKey}.';
    });
  }

  Future<void> _openMatchTeamPicker() async {
    final matches = eventController.matches;
    if (matches.isEmpty) return;

    final selected = await showDialog<StatboticsMatch>(
      context: context,
      builder: (ctx) => _MatchTeamPickerDialog(
        matches: matches,
        initialMatch: _selectedMatch,
        eventController: eventController,
      ),
    );
    if (!mounted) return;
    if (selected == null) return;

    setState(() {
      _selectedMatch = selected;
    });
  }

  void _loadMatchTeams(
    StatboticsMatch match, {
    bool redOnly = false,
    bool blueOnly = false,
  }) {
    final teams = <int>[];
    if (!blueOnly) teams.addAll(match.redTeams);
    if (!redOnly) teams.addAll(match.blueTeams);
    controller.importTeams(teams);
    controller.setEventKey(eventController.eventKey);
    if (eventController.eventName.isNotEmpty) {
      controller.setEventName(eventController.eventName);
      _eventController.value = _eventController.value.copyWith(
        text: eventController.eventName,
        selection: TextSelection.collapsed(
          offset: eventController.eventName.length,
        ),
        composing: TextRange.empty,
      );
    }
    setState(() {
      _statusMessage =
          'Loaded ${teams.length} teams from ${match.displayName}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, eventController]),
      builder: (context, child) {
        if (!controller.isReady) {
          return const Center(child: CircularProgressIndicator());
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1100;
            final board = _buildBoardSection(context);
            final sidebar = _buildSidebar(context);
            if (isWide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: board),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: sidebar),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [board, const SizedBox(height: 16), sidebar],
            );
          },
        );
      },
    );
  }

  Widget _buildBoardSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _eventController,
                        decoration: const InputDecoration(
                          labelText: 'Event name',
                        ),
                        onChanged: controller.setEventName,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _matchController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Match #'),
                        onChanged: controller.setMatchNumber,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final available = controller.teamsAvailableInPhase(
                          controller.session.selectedPhase,
                        );
                        final selected = controller.session.selectedRobotTeam;
                        final value = available.contains(selected)
                            ? selected
                            : null;
                        final allPlaced =
                            controller.session.teamNumbers.isNotEmpty &&
                            available.isEmpty;
                        return DropdownButton<int?>(
                          value: value,
                          hint: Text(
                            allPlaced ? 'All teams placed' : 'Robot team',
                          ),
                          onChanged: controller.setSelectedRobotTeam,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Robot team'),
                            ),
                            ...available.map(
                              (team) => DropdownMenuItem<int?>(
                                value: team,
                                child: Text(team.toString()),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    DropdownButton<String>(
                      value:
                          const [
                            'Red',
                            'Blue',
                          ].contains(controller.session.alliance)
                          ? controller.session.alliance
                          : 'Red',
                      onChanged: (value) {
                        if (value != null) {
                          controller.setAlliance(value);
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 'Red', child: Text('Red')),
                        DropdownMenuItem(value: 'Blue', child: Text('Blue')),
                      ],
                    ),
                    FutureBuilder<FieldMapCatalogData>(
                      future: _fieldCatalogFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasError) {
                          return _fieldCatalogError();
                        }
                        final fields =
                            snapshot.data?.fields ??
                            const <FieldMapDefinition>[];
                        final selected = snapshot.data?.fallbackFor(
                          controller.session.selectedFieldId,
                        );
                        if (fields.isEmpty || selected == null) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Field',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                            ),
                            DropdownButton<String>(
                              value: selected.id,
                              onChanged: (value) {
                                if (value != null) {
                                  controller.selectField(value);
                                }
                              },
                              items: fields
                                  .map(
                                    (field) => DropdownMenuItem<String>(
                                      value: field.id,
                                      child: Text(field.game),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                HorizontalStepShortcuts(
                  onPrevious: () => _stepPhase(controller, -1),
                  onNext: () => _stepPhase(controller, 1),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: StrategyPhase.values
                        .map((phase) {
                          final selected =
                              controller.session.selectedPhase == phase;
                          return ChoiceChip(
                            label: Text(phase.label),
                            selected: selected,
                            onSelected: (_) => controller.selectPhase(phase),
                            selectedColor: StrategyPalette.phaseColor(phase),
                            labelStyle: TextStyle(
                              color: selected
                                  ? StrategyPalette.onPhaseColor(phase)
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: StrategyTool.values
                      .map((tool) {
                        final selected =
                            controller.session.selectedTool == tool;
                        return OutlinedButton.icon(
                          onPressed: () => controller.selectTool(tool),
                          icon: Icon(
                            tool == StrategyTool.draw
                                ? Icons.edit_rounded
                                : tool == StrategyTool.robot
                                ? Icons.smart_toy_rounded
                                : Icons.delete_outline_rounded,
                          ),
                          label: Text(tool.label),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selected
                                ? Theme.of(context).colorScheme.secondary
                                : Colors.transparent,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _toolHint(controller.session.selectedTool),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<FieldMapCatalogData>(
                  future: _fieldCatalogFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      debugPrint(
                        'FieldMapCatalog load error: ${snapshot.error}',
                      );
                    }
                    final selected = snapshot.data?.fallbackFor(
                      controller.session.selectedFieldId,
                    );
                    return StrategyFieldCanvas(
                      controller: controller,
                      repaintKey: _boardKey,
                      backgroundImageAsset: selected?.imageAsset,
                      fieldAspectRatio: selected?.aspectRatio ?? 2.0,
                      onElementErased: _showEraseUndo,
                      teamAvatarService: widget.teamAvatarService,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final session = controller.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Teams',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (session.teamNumbers.isNotEmpty)
                      TextButton.icon(
                        onPressed: controller.clearTeams,
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        label: const Text('Clear'),
                      ),
                    TextButton.icon(
                      onPressed: _importTeams,
                      icon: const Icon(Icons.upload_file_rounded, size: 16),
                      label: const Text('Import'),
                    ),
                  ],
                ),
                if (eventController.hasMatches) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openMatchTeamPicker,
                          icon: const Icon(
                            Icons.sports_esports_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _selectedMatch != null
                                ? 'Match ${_selectedMatch!.displayName}'
                                : 'Pick match',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedMatch != null) ...[
                    const SizedBox(height: 8),
                    _MatchAllianceRow(
                      label: 'Red',
                      teams: _selectedMatch!.redTeams,
                      color: StrategyPalette.allianceRed,
                      activeTeams: session.teamNumbers,
                      nicknames: eventController.teamNicknames,
                      onTeamTap: (team) {
                        if (session.teamNumbers.contains(team)) {
                          controller.removeTeam(team);
                        } else {
                          controller.addTeam(team);
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    _MatchAllianceRow(
                      label: 'Blue',
                      teams: _selectedMatch!.blueTeams,
                      color: StrategyPalette.allianceBlue,
                      activeTeams: session.teamNumbers,
                      nicknames: eventController.teamNicknames,
                      onTeamTap: (team) {
                        if (session.teamNumbers.contains(team)) {
                          controller.removeTeam(team);
                        } else {
                          controller.addTeam(team);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _loadMatchTeams(_selectedMatch!, redOnly: true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: StrategyPalette.allianceRed,
                            ),
                            child: const Text('Load red'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _loadMatchTeams(_selectedMatch!),
                            child: const Text('Load all 6'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _loadMatchTeams(
                              _selectedMatch!,
                              blueOnly: true,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: StrategyPalette.allianceBlue,
                            ),
                            child: const Text('Load blue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else if (eventController.hasEvent &&
                    eventController.teamNumbers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: eventController.isLoading
                        ? null
                        : _loadTeamsFromEvent,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Load all event teams'),
                  ),
                ],
                if (session.teamNumbers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: session.teamNumbers
                        .map((team) {
                          final selected = session.selectedRobotTeam == team;
                          return FilterChip(
                            label: Text(team.toString()),
                            selected: selected,
                            onSelected: (_) =>
                                controller.setSelectedRobotTeam(team),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => controller.removeTeam(team),
                            selectedColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            labelStyle: TextStyle(
                              color: selected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: controller.autoPlaceTeams,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Auto-place on field'),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Pick a match above or import a roster to load teams.',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Phase note',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Phase notes',
                    hintText: 'Capture what this phase should do',
                  ),
                  onChanged: controller.updateNote,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _clearWithUndo(
                          message: 'Phase cleared',
                          action: controller.clearSelectedPhase,
                        ),
                        child: const Text('Clear phase'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _clearWithUndo(
                          message: 'Board cleared',
                          action: controller.clearAll,
                        ),
                        child: const Text('Clear all'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_statusMessage != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_statusMessage!),
            ),
          ),
      ],
    );
  }
}

class _MatchPickerSheet extends StatefulWidget {
  const _MatchPickerSheet({
    required this.controller,
    required this.eventKey,
    required this.eventName,
  });

  final String eventKey;

  final String eventName;

  final StrategyController controller;

  @override
  State<_MatchPickerSheet> createState() => _MatchPickerSheetState();
}

class _MatchPickerSheetState extends State<_MatchPickerSheet> {
  late bool _thisEventOnly = widget.eventKey.isNotEmpty;

  late Future<List<MatchSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.listMatches();
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _reload() {
    setState(() {
      _future = widget.controller.listMatches();
    });
  }

  Future<void> _createMatch() async {
    await widget.controller.createMatch(
      eventKey: widget.eventKey.isEmpty ? null : widget.eventKey,
      eventName: widget.eventName.trim().isEmpty ? null : widget.eventName,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _openMatch(String id) async {
    await widget.controller.openMatch(id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _openRemoteBoard(String id) async {
    await widget.controller.openRemoteBoard(id);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(MatchSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete match?'),
          content: Text(
            'This will remove "${summary.title}" and its drawings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.deleteMatch(summary.id);
    if (!mounted) {
      return;
    }
    _reload();
  }

  String _formatTimestamp(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final activeId = widget.controller.session.id;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final remoteBoards = widget.controller.remoteBoards;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Matches',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),

                Flexible(
                  child: _BoardSyncPill(
                    status: widget.controller.syncStatus,
                    failedWrites: widget.controller.failedWrites,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _createMatch,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New match'),
            ),
            if (widget.eventKey.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildScopeToggle(context),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<MatchSummary>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final lists = scopeBoardLists(
                    allMatches: snapshot.data ?? <MatchSummary>[],
                    remoteBoards: remoteBoards,
                    selectedEventKey: widget.eventKey,
                    thisEventOnly: _thisEventOnly,
                  );
                  final matches = lists.matches;
                  final teamBoards = lists.teamBoards;
                  final hidden = lists.hidden;

                  if (lists.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        hidden > 0
                            ? 'No boards for this event yet. $hidden from other '
                                  'events are hidden.'
                            : 'No saved matches yet.',
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < matches.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _buildMatchTile(matches[i], activeId),
                      ],
                      if (teamBoards.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionHeader(
                          label: 'Team boards',
                          hint: 'Drawn by teammates. Tap to open.',
                        ),
                        const SizedBox(height: 8),
                        for (final board in teamBoards)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildTeamBoardTile(board),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeToggle(BuildContext context) {
    final String label = widget.eventName.trim().isEmpty
        ? 'This event only'
        : 'This event only (${widget.eventName.trim()})';

    return Row(
      children: [
        Flexible(
          child: FilterChip(
            selected: _thisEventOnly,
            onSelected: (bool value) => setState(() => _thisEventOnly = value),
            avatar: Icon(
              _thisEventOnly
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_off_outlined,
              size: 18,
            ),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchTile(MatchSummary match, String activeId) {
    final isActive = match.id == activeId;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: ListTile(
        tileColor: isActive ? cs.secondary : cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StrategyPalette.radiusSm),
          ),
        ),
        leading: Icon(
          isActive
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: cs.primary,
        ),
        title: Text(match.title),
        subtitle: Text(
          'Alliance ${match.alliance} - '
          '${_formatTimestamp(match.updatedAt)}',
        ),
        trailing: IconButton(
          onPressed: () => _confirmDelete(match),
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete match',
        ),
        onTap: () => _openMatch(match.id),
        onLongPress: () => _confirmDelete(match),
      ),
    );
  }

  Widget _buildTeamBoardTile(StrategySession board) {
    final authorName = board.authorDisplayName ?? '';
    final subtitle = authorName.isNotEmpty ? 'by $authorName' : 'by a teammate';
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: ListTile(
        tileColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(StrategyPalette.radiusSm),
          ),
        ),
        title: Text(board.title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.download_rounded),
        onTap: () => _openRemoteBoard(board.id),
      ),
    );
  }
}

class _MatchAllianceRow extends StatelessWidget {
  const _MatchAllianceRow({
    required this.label,
    required this.teams,
    required this.color,
    required this.activeTeams,
    required this.nicknames,
    required this.onTeamTap,
  });

  final String label;
  final List<int> teams;
  final Color color;
  final List<int> activeTeams;
  final Map<int, String> nicknames;
  final ValueChanged<int> onTeamTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: teams
                .map((team) {
                  final isActive = activeTeams.contains(team);
                  final nick = nicknames[team];
                  return FilterChip(
                    label: Text(
                      nick != null && nick.isNotEmpty
                          ? '$team\n$nick'
                          : team.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? Colors.white : color,
                      ),
                    ),
                    selected: isActive,
                    onSelected: (_) => onTeamTap(team),
                    selectedColor: color,
                    checkmarkColor: Colors.white,
                    side: BorderSide(color: color),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _MatchTeamPickerDialog extends StatefulWidget {
  const _MatchTeamPickerDialog({
    required this.matches,
    required this.eventController,
    this.initialMatch,
  });

  final List<StatboticsMatch> matches;
  final EventController eventController;
  final StatboticsMatch? initialMatch;

  @override
  State<_MatchTeamPickerDialog> createState() => _MatchTeamPickerDialogState();
}

class _MatchTeamPickerDialogState extends State<_MatchTeamPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StatboticsMatch> get _filtered {
    if (_query.isEmpty) return widget.matches;
    return widget.matches
        .where((m) => m.displayName.toLowerCase().contains(_query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: const Text('Select Match'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Filter matches...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final match = filtered[index];
                  return MatchScheduleRow(
                    match: match,
                    nicknames: widget.eventController.teamNicknames,
                    selected: widget.initialMatch?.key == match.key,
                    onTap: () => Navigator.of(context).pop(match),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _BoardSyncPill extends StatelessWidget {
  const _BoardSyncPill({required this.status, required this.failedWrites});

  final StrategyBoardSyncStatus status;

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    if (failedWrites.hasFailures) {
      final count = failedWrites.unlandedCount;
      return SyncStatusPill(
        label: '$count edit${count == 1 ? '' : 's'} not saved',
        icon: Icons.cloud_off_rounded,
        isFailure: true,
      );
    }

    final (String label, IconData icon) = switch (status.state) {
      StrategyBoardSyncState.signedOut => (
        'Not signed in to sync',
        Icons.cloud_off_rounded,
      ),
      StrategyBoardSyncState.noAccess => (
        'No team access yet',
        Icons.lock_outline_rounded,
      ),
      StrategyBoardSyncState.syncing => ('Syncing...', Icons.sync_rounded),
      StrategyBoardSyncState.synced => ('Synced', Icons.cloud_done_rounded),
      StrategyBoardSyncState.offline => ('Offline', Icons.cloud_off_rounded),
    };

    return SyncStatusPill(label: label, icon: icon);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
