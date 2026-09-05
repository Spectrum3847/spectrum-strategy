import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trex_assignments.dart';
import '../models/trex_team_list.dart';
import '../services/trex_assignments_export.dart';
import '../services/trex_team_list_export.dart';
import '../state/failed_write_tracker.dart';
import '../state/trex_assignments_controller.dart';
import '../state/trex_team_list_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/paste_list_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/sync_status_pill.dart';

class TRexAssignmentsView extends StatefulWidget {
  const TRexAssignmentsView({
    required this.controller,
    this.teamListController,
    this.canEdit = false,
    super.key,
  });

  final TRexAssignmentsController controller;

  final TRexTeamListController? teamListController;

  final bool canEdit;

  @override
  State<TRexAssignmentsView> createState() => _TRexAssignmentsViewState();
}

class _TRexAssignmentsViewState extends State<TRexAssignmentsView> {
  final TextEditingController _newColumnController = TextEditingController();

  @override
  void dispose() {
    _newColumnController.dispose();
    super.dispose();
  }

  Future<void> _copyAsText() async {
    final buffer = StringBuffer(
      TRexAssignmentsExport.asText(widget.controller.assignments),
    );
    final teamListController = widget.teamListController;
    if (teamListController != null) {
      buffer.writeln();
      buffer.writeln();
      buffer.write(TRexTeamListExport.asText(teamListController.teamList));
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('T-Rex assignments copied as text')),
    );
  }

  void _addColumn() {
    final name = _newColumnController.text;
    if (name.trim().isEmpty) return;
    widget.controller.addColumn(name);
    _newColumnController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final teamListController = widget.teamListController;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, teamListController]),
      builder: (context, _) {
        if (widget.controller.isLoading ||
            (teamListController?.isLoading ?? false)) {
          return const Center(child: CircularProgressIndicator());
        }
        final assignments = widget.controller.assignments;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),

              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (widget.controller.failedWrites.hasFailures)
                        _TRexSyncPill(
                          failedWrites: widget.controller.failedWrites,
                        ),
                      if (teamListController != null &&
                          teamListController.failedWrites.hasFailures)
                        _TRexSyncPill(
                          failedWrites: teamListController.failedWrites,
                        ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyAsText,
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('Copy as text'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    assignments.isEmpty
                        ? EmptyState(
                            icon: Icons.groups_2_outlined,
                            message: widget.canEdit
                                ? 'No T-Rex traits yet. Add one below to '
                                      'start assigning student scouters.'
                                : 'No T-Rex traits have been added yet.',
                          )
                        : _ColumnsList(
                            controller: widget.controller,
                            columns: assignments.columns,
                            canEdit: widget.canEdit,
                          ),
                    if (widget.canEdit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newColumnController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  hintText: 'New trait, e.g. Defense',
                                ),
                                onSubmitted: (_) => _addColumn(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _addColumn,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add trait'),
                            ),
                          ],
                        ),
                      ),
                    if (teamListController != null) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          'Team assignments',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _TeamListSection(
                        controller: teamListController,
                        canEdit: widget.canEdit,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ColumnsList extends StatelessWidget {
  const _ColumnsList({
    required this.controller,
    required this.columns,
    required this.canEdit,
  });

  final TRexAssignmentsController controller;
  final List<TRexTraitColumn> columns;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < columns.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 240,
                child: _ColumnCard(
                  controller: controller,
                  column: columns[i],
                  canEdit: canEdit,
                  canMoveLeft: i > 0,
                  canMoveRight: i < columns.length - 1,

                  onMove: (delta) =>
                      controller.reorderColumns(i, delta < 0 ? i - 1 : i + 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnCard extends StatefulWidget {
  const _ColumnCard({
    required this.controller,
    required this.column,
    required this.canEdit,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onMove,
  });

  final TRexAssignmentsController controller;
  final TRexTraitColumn column;
  final bool canEdit;
  final bool canMoveLeft;
  final bool canMoveRight;

  final void Function(int delta) onMove;

  @override
  State<_ColumnCard> createState() => _ColumnCardState();
}

class _ColumnCardState extends State<_ColumnCard> {
  late final TextEditingController _headerText = TextEditingController(
    text: widget.column.name,
  );
  final TextEditingController _newNameText = TextEditingController();
  Timer? _headerDebounce;

  static const _debounceFor = Duration(milliseconds: 600);

  @override
  void didUpdateWidget(_ColumnCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.column.name != widget.column.name &&
        _headerText.text != widget.column.name &&
        _headerDebounce == null) {
      _headerText.text = widget.column.name;
    }
  }

  @override
  void dispose() {
    _headerDebounce?.cancel();
    _saveHeader();
    _headerText.dispose();
    _newNameText.dispose();
    super.dispose();
  }

  void _onHeaderChanged(String _) {
    _headerDebounce?.cancel();
    _headerDebounce = Timer(_debounceFor, _saveHeader);
  }

  void _saveHeader() {
    _headerDebounce = null;
    final value = _headerText.text;
    if (value == widget.column.name) return;

    if (value.trim().isEmpty) {
      _headerText.text = widget.column.name;
      return;
    }
    widget.controller.renameColumn(widget.column.key, value);
  }

  void _addName() {
    final name = _newNameText.text;
    if (name.trim().isEmpty) return;
    widget.controller.addName(widget.column.key, name);
    _newNameText.clear();
  }

  Future<void> _pasteNames() async {
    final names = await showPasteListDialog(
      context,
      title: 'Paste scouters',
      hint: 'Ada Lovelace\nGrace Hopper\n...',
    );
    if (names == null || names.isEmpty) return;
    await widget.controller.addNames(widget.column.key, names);
  }

  Future<void> _confirmDeleteColumn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove trait?'),
        content: Text(
          'This removes "${widget.column.name}" and everyone assigned '
          'to it from the T-Rex table.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.controller.removeColumn(widget.column.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: widget.canEdit
                    ? TextField(
                        controller: _headerText,
                        onChanged: _onHeaderChanged,
                        onSubmitted: (_) => _saveHeader(),
                        onTapOutside: (_) => _saveHeader(),
                        style: Theme.of(context).textTheme.titleSmall,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(
                        widget.column.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
              ),
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  tooltip: 'Move trait left',
                  onPressed: widget.canMoveLeft
                      ? () => widget.onMove(-1)
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  tooltip: 'Move trait right',
                  onPressed: widget.canMoveRight
                      ? () => widget.onMove(1)
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove trait',
                  onPressed: _confirmDeleteColumn,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const Divider(height: 12),
          if (widget.column.names.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No one assigned yet',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < widget.column.names.length; i++)
              _NameRow(
                controller: widget.controller,
                columnKey: widget.column.key,
                index: i,
                name: widget.column.names[i],
                canEdit: widget.canEdit,
                canMoveUp: i > 0,
                canMoveDown: i < widget.column.names.length - 1,
              ),
          if (widget.canEdit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newNameText,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'Add scouter',
                      ),
                      onSubmitted: (_) => _addName(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('trex-paste-names-${widget.column.key}'),
                    tooltip: 'Paste a list of scouters',
                    onPressed: _pasteNames,
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NameRow extends StatefulWidget {
  const _NameRow({
    required this.controller,
    required this.columnKey,
    required this.index,
    required this.name,
    required this.canEdit,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final TRexAssignmentsController controller;
  final String columnKey;
  final int index;
  final String name;
  final bool canEdit;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  State<_NameRow> createState() => _NameRowState();
}

class _NameRowState extends State<_NameRow> {
  late final TextEditingController _text = TextEditingController(
    text: widget.name,
  );
  Timer? _debounce;

  static const _debounceFor = Duration(milliseconds: 600);

  @override
  void didUpdateWidget(_NameRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name &&
        _text.text != widget.name &&
        _debounce == null) {
      _text.text = widget.name;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_debounceFor, _save);
  }

  void _save() {
    _debounce = null;
    final value = _text.text;
    if (value == widget.name) return;

    if (value.trim().isEmpty) {
      _text.text = widget.name;
      return;
    }
    widget.controller.renameName(widget.columnKey, widget.index, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: widget.canEdit
                ? TextField(
                    controller: _text,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _save(),
                    onTapOutside: (_) => _save(),
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      widget.name,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
          ),
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              onPressed: widget.canMoveUp ? _moveUp : null,
            ),
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.arrow_downward_rounded, size: 16),
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              onPressed: widget.canMoveDown ? _moveDown : null,
            ),
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  widget.controller.removeName(widget.columnKey, widget.index),
            ),
        ],
      ),
    );
  }

  void _moveUp() {
    widget.controller.reorderNames(
      widget.columnKey,
      widget.index,
      widget.index - 1,
    );
  }

  void _moveDown() {
    widget.controller.reorderNames(
      widget.columnKey,
      widget.index,
      widget.index + 2,
    );
  }
}

class _TRexSyncPill extends StatelessWidget {
  const _TRexSyncPill({required this.failedWrites});

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    final count = failedWrites.unlandedCount;
    return SyncStatusPill(
      label: '$count edit${count == 1 ? '' : 's'} not saved',
      icon: Icons.cloud_off_rounded,
      isFailure: true,
    );
  }
}

class _TeamListSection extends StatefulWidget {
  const _TeamListSection({required this.controller, required this.canEdit});

  final TRexTeamListController controller;
  final bool canEdit;

  @override
  State<_TeamListSection> createState() => _TeamListSectionState();
}

class _TeamListSectionState extends State<_TeamListSection> {
  late final TextEditingController _titleText = TextEditingController(
    text: widget.controller.teamList.title,
  );
  final TextEditingController _newColumnController = TextEditingController();
  Timer? _titleDebounce;

  static const _debounceFor = Duration(milliseconds: 600);

  @override
  void dispose() {
    _titleDebounce?.cancel();
    _saveTitle();
    _titleText.dispose();
    _newColumnController.dispose();
    super.dispose();
  }

  void _onTitleChanged(String _) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(_debounceFor, _saveTitle);
  }

  void _saveTitle() {
    _titleDebounce = null;
    final value = _titleText.text;
    if (value == widget.controller.teamList.title) return;
    widget.controller.setTitle(value);
  }

  void _addColumn() {
    final name = _newColumnController.text;
    if (name.trim().isEmpty) return;
    widget.controller.addColumn(name);
    _newColumnController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final teamList = widget.controller.teamList;

    if (_titleText.text != teamList.title && _titleDebounce == null) {
      _titleText.text = teamList.title;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: widget.canEdit
              ? TextField(
                  controller: _titleText,
                  onChanged: _onTitleChanged,
                  onSubmitted: (_) => _saveTitle(),
                  onTapOutside: (_) => _saveTitle(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    labelText: 'Title',
                    hintText: 'Pit Scouting Team Assignments',
                  ),
                )
              : Text(
                  teamList.title.isEmpty
                      ? 'Pit Scouting Team Assignments'
                      : teamList.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
        ),
        const SizedBox(height: 8),
        teamList.isEmpty
            ? EmptyState(
                icon: Icons.list_alt_rounded,
                message: widget.canEdit
                    ? 'No columns yet. Add one below to start listing '
                          'teams per trait.'
                    : 'No team assignments have been added yet.',
              )
            : _TeamColumnsList(
                controller: widget.controller,
                columns: teamList.columns,
                canEdit: widget.canEdit,
              ),
        if (widget.canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newColumnController,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: 'New trait column, e.g. Defense',
                    ),
                    onSubmitted: (_) => _addColumn(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add column'),
                ),
              ],
            ),
          ),
        if (!teamList.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Total teams: ${teamList.totalTeams}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _TeamColumnsList extends StatelessWidget {
  const _TeamColumnsList({
    required this.controller,
    required this.columns,
    required this.canEdit,
  });

  final TRexTeamListController controller;
  final List<TRexTeamListColumn> columns;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < columns.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 200,
                child: _TeamColumnCard(
                  controller: controller,
                  column: columns[i],
                  canEdit: canEdit,
                  canMoveLeft: i > 0,
                  canMoveRight: i < columns.length - 1,

                  onMove: (delta) =>
                      controller.reorderColumns(i, delta < 0 ? i - 1 : i + 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamColumnCard extends StatefulWidget {
  const _TeamColumnCard({
    required this.controller,
    required this.column,
    required this.canEdit,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onMove,
  });

  final TRexTeamListController controller;
  final TRexTeamListColumn column;
  final bool canEdit;
  final bool canMoveLeft;
  final bool canMoveRight;

  final void Function(int delta) onMove;

  @override
  State<_TeamColumnCard> createState() => _TeamColumnCardState();
}

class _TeamColumnCardState extends State<_TeamColumnCard> {
  late final TextEditingController _headerText = TextEditingController(
    text: widget.column.name,
  );
  final TextEditingController _newTeamText = TextEditingController();
  Timer? _headerDebounce;

  static const _debounceFor = Duration(milliseconds: 600);

  @override
  void didUpdateWidget(_TeamColumnCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.column.name != widget.column.name &&
        _headerText.text != widget.column.name &&
        _headerDebounce == null) {
      _headerText.text = widget.column.name;
    }
  }

  @override
  void dispose() {
    _headerDebounce?.cancel();
    _saveHeader();
    _headerText.dispose();
    _newTeamText.dispose();
    super.dispose();
  }

  void _onHeaderChanged(String _) {
    _headerDebounce?.cancel();
    _headerDebounce = Timer(_debounceFor, _saveHeader);
  }

  void _saveHeader() {
    _headerDebounce = null;
    final value = _headerText.text;
    if (value == widget.column.name) return;
    if (value.trim().isEmpty) {
      _headerText.text = widget.column.name;
      return;
    }
    widget.controller.renameColumn(widget.column.key, value);
  }

  void _addTeam() {
    final team = _newTeamText.text;
    if (team.trim().isEmpty) return;
    widget.controller.addTeam(widget.column.key, team);
    _newTeamText.clear();
  }

  Future<void> _pasteTeams() async {
    final teams = await showPasteListDialog(
      context,
      title: 'Paste teams',
      hint: '3847\n254\n1678\n...',
    );
    if (teams == null || teams.isEmpty) return;
    await widget.controller.addTeams(widget.column.key, teams);
  }

  Future<void> _confirmDeleteColumn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove column?'),
        content: Text(
          'This removes "${widget.column.name}" and every team listed '
          'under it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.controller.removeColumn(widget.column.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: widget.canEdit
                    ? TextField(
                        controller: _headerText,
                        onChanged: _onHeaderChanged,
                        onSubmitted: (_) => _saveHeader(),
                        onTapOutside: (_) => _saveHeader(),
                        style: Theme.of(context).textTheme.titleSmall,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(
                        widget.column.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
              ),
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  tooltip: 'Move column left',
                  onPressed: widget.canMoveLeft
                      ? () => widget.onMove(-1)
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  tooltip: 'Move column right',
                  onPressed: widget.canMoveRight
                      ? () => widget.onMove(1)
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove column',
                  onPressed: _confirmDeleteColumn,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const Divider(height: 12),
          if (widget.column.teams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No teams yet',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < widget.column.teams.length; i++)
              _TeamRow(
                controller: widget.controller,
                columnKey: widget.column.key,
                index: i,
                team: widget.column.teams[i],
                canEdit: widget.canEdit,
                canMoveUp: i > 0,
                canMoveDown: i < widget.column.teams.length - 1,
              ),
          if (widget.canEdit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTeamText,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'Add team',
                      ),
                      onSubmitted: (_) => _addTeam(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('trex-paste-teams-${widget.column.key}'),
                    tooltip: 'Paste a list of teams',
                    onPressed: _pasteTeams,
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatefulWidget {
  const _TeamRow({
    required this.controller,
    required this.columnKey,
    required this.index,
    required this.team,
    required this.canEdit,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final TRexTeamListController controller;
  final String columnKey;
  final int index;
  final String team;
  final bool canEdit;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  State<_TeamRow> createState() => _TeamRowState();
}

class _TeamRowState extends State<_TeamRow> {
  late final TextEditingController _text = TextEditingController(
    text: widget.team,
  );
  Timer? _debounce;

  static const _debounceFor = Duration(milliseconds: 600);

  @override
  void didUpdateWidget(_TeamRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team != widget.team &&
        _text.text != widget.team &&
        _debounce == null) {
      _text.text = widget.team;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_debounceFor, _save);
  }

  void _save() {
    _debounce = null;
    final value = _text.text;
    if (value == widget.team) return;
    if (value.trim().isEmpty) {
      _text.text = widget.team;
      return;
    }
    widget.controller.renameTeam(widget.columnKey, widget.index, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: widget.canEdit
                ? TextField(
                    controller: _text,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _save(),
                    onTapOutside: (_) => _save(),
                    keyboardType: TextInputType.number,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      widget.team,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
          ),
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              onPressed: widget.canMoveUp ? _moveUp : null,
            ),
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.arrow_downward_rounded, size: 16),
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              onPressed: widget.canMoveDown ? _moveDown : null,
            ),
          if (widget.canEdit)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  widget.controller.removeTeam(widget.columnKey, widget.index),
            ),
        ],
      ),
    );
  }

  void _moveUp() {
    widget.controller.reorderTeams(
      widget.columnKey,
      widget.index,
      widget.index - 1,
    );
  }

  void _moveDown() {
    widget.controller.reorderTeams(
      widget.columnKey,
      widget.index,
      widget.index + 2,
    );
  }
}
