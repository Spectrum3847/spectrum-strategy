import 'package:flutter/material.dart';

import '../../theme/strategy_palette.dart';
import '../../widgets/glass_modal.dart';
import '../models/scout_shift_schedule.dart';

class ScoutShiftGrid extends StatefulWidget {
  const ScoutShiftGrid({
    required this.schedule,
    required this.canEdit,
    this.onCellEdit,
    this.onCellsEdit,
    this.onRenameColumn,
    super.key,
  });

  final ScoutShiftSchedule schedule;
  final bool canEdit;

  final void Function(
    int col,
    int match,
    String text,
    ScheduleCellColor? color,
  )?
  onCellEdit;

  final void Function(
    List<(int col, int match)> cells,
    String text,
    ScheduleCellColor? color,
  )?
  onCellsEdit;

  final void Function(int col, String name)? onRenameColumn;

  static const double numberColumnWidth = 56;
  static const double nameColumnWidth = 104;
  static const double rowHeight = 40;

  @override
  State<ScoutShiftGrid> createState() => _ScoutShiftGridState();
}

class _ScoutShiftGridState extends State<ScoutShiftGrid> {
  final ScrollController _headerHorizontal = ScrollController();
  final ScrollController _bodyHorizontal = ScrollController();
  final ScrollController _bodyVertical = ScrollController();

  (int, int)? _selectionAnchor;
  (int, int)? _selectionCurrent;

  @override
  void initState() {
    super.initState();
    _bodyHorizontal.addListener(_syncHeaderScroll);
  }

  void _syncHeaderScroll() {
    if (_headerHorizontal.hasClients) {
      _headerHorizontal.jumpTo(_bodyHorizontal.offset);
    }
  }

  @override
  void dispose() {
    _bodyHorizontal.removeListener(_syncHeaderScroll);
    _headerHorizontal.dispose();
    _bodyHorizontal.dispose();
    _bodyVertical.dispose();
    super.dispose();
  }

  (int, int)? _cellAt(Offset local) {
    final schedule = widget.schedule;
    final x =
        local.dx + (_bodyHorizontal.hasClients ? _bodyHorizontal.offset : 0);
    final y = local.dy + (_bodyVertical.hasClients ? _bodyVertical.offset : 0);
    if (x < ScoutShiftGrid.numberColumnWidth || y < 0) return null;
    final col =
        ((x - ScoutShiftGrid.numberColumnWidth) /
                ScoutShiftGrid.nameColumnWidth)
            .floor();
    final match = (y / ScoutShiftGrid.rowHeight).floor() + 1;
    if (col < 0 || col >= schedule.roster.length) return null;
    if (match < 1 || match > schedule.matchCount) return null;
    return (col, match);
  }

  List<(int, int)> _cellsInRect((int, int) a, (int, int) b) {
    final colMin = a.$1 <= b.$1 ? a.$1 : b.$1;
    final colMax = a.$1 <= b.$1 ? b.$1 : a.$1;
    final matchMin = a.$2 <= b.$2 ? a.$2 : b.$2;
    final matchMax = a.$2 <= b.$2 ? b.$2 : a.$2;
    return [
      for (var c = colMin; c <= colMax; c++)
        for (var m = matchMin; m <= matchMax; m++) (c, m),
    ];
  }

  Set<(int, int)> get _selectedCells {
    final anchor = _selectionAnchor;
    final current = _selectionCurrent;
    if (anchor == null || current == null) return const <(int, int)>{};
    return _cellsInRect(anchor, current).toSet();
  }

  void _startSelection(Offset local) {
    final cell = _cellAt(local);
    if (cell == null) return;
    setState(() {
      _selectionAnchor = cell;
      _selectionCurrent = cell;
    });
  }

  void _updateSelection(Offset local) {
    if (_selectionAnchor == null) return;
    final cell = _cellAt(local);
    if (cell == null) return;
    setState(() => _selectionCurrent = cell);
  }

  void _cancelSelection() {
    if (_selectionAnchor == null) return;
    setState(() {
      _selectionAnchor = null;
      _selectionCurrent = null;
    });
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(() {
      _selectionAnchor = null;
      _selectionCurrent = null;
    });
  }

  Future<void> _finishSelection() async {
    final anchor = _selectionAnchor;
    final current = _selectionCurrent;
    if (anchor == null || current == null || !widget.canEdit) {
      _clearSelection();
      return;
    }
    final schedule = widget.schedule;

    final cells = _cellsInRect(anchor, current)
        .where(
          (c) =>
              c.$1 >= 0 &&
              c.$1 < schedule.roster.length &&
              c.$2 >= 1 &&
              c.$2 <= schedule.matchCount,
        )
        .toList();
    if (cells.isEmpty) {
      _clearSelection();
      return;
    }

    final initialText = schedule.textFor(cells.first.$1, cells.first.$2);
    final initialColor = schedule.colorFor(cells.first.$1, cells.first.$2);
    final formKey = GlobalKey<_CellEditDialogState>();
    final result = await showGlassConfirmDialog<_CellEditResult>(
      context: context,
      title: cells.length > 1 ? 'Edit ${cells.length} cells' : 'Edit cell',
      content: _CellEditDialog(
        key: formKey,
        initialText: initialText,
        initialColor: initialColor,
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => formKey.currentState?.submit(),
          child: const Text('Save'),
        ),
      ],
    );
    _clearSelection();
    if (result == null) return;
    widget.onCellsEdit?.call(cells, result.text, result.color);
  }

  Future<void> _editCell(int col, int match) async {
    if (!widget.canEdit) return;
    final initialText = widget.schedule.textFor(col, match);
    final initialColor = widget.schedule.colorFor(col, match);
    final formKey = GlobalKey<_CellEditDialogState>();
    final result = await showGlassConfirmDialog<_CellEditResult>(
      context: context,
      title: 'Edit cell',
      content: _CellEditDialog(
        key: formKey,
        initialText: initialText,
        initialColor: initialColor,
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => formKey.currentState?.submit(),
          child: const Text('Save'),
        ),
      ],
    );
    if (result == null) return;

    if (result.text == initialText && result.color == initialColor) return;
    widget.onCellEdit?.call(col, match, result.text, result.color);
  }

  Future<void> _renameColumn(int col) async {
    if (!widget.canEdit) return;
    final formKey = GlobalKey<_RenameDialogState>();
    final name = await showGlassConfirmDialog<String>(
      context: context,
      title: 'Rename scouter',
      content: _RenameDialog(
        key: formKey,
        initialName: widget.schedule.roster[col].name,
      ),
      actionsBuilder: (dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => formKey.currentState?.submit(),
          child: const Text('Save'),
        ),
      ],
    );
    if (name == null || name.isEmpty) return;
    widget.onRenameColumn?.call(col, name);
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    final columnCount = schedule.roster.length;
    final width =
        ScoutShiftGrid.numberColumnWidth +
        ScoutShiftGrid.nameColumnWidth * columnCount;

    return Column(
      children: [
        SingleChildScrollView(
          controller: _headerHorizontal,
          scrollDirection: Axis.horizontal,

          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(width: width, child: _headerRow(context, schedule)),
        ),
        Expanded(
          child: GestureDetector(
            onLongPressStart: widget.canEdit
                ? (details) => _startSelection(details.localPosition)
                : null,
            onLongPressMoveUpdate: widget.canEdit
                ? (details) => _updateSelection(details.localPosition)
                : null,
            onLongPressEnd: widget.canEdit ? (_) => _finishSelection() : null,
            onLongPressCancel: widget.canEdit ? _cancelSelection : null,
            child: Scrollbar(
              controller: _bodyHorizontal,
              child: SingleChildScrollView(
                controller: _bodyHorizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: ListView.builder(
                    controller: _bodyVertical,
                    itemCount: schedule.matchCount,
                    itemBuilder: (context, index) =>
                        _matchRow(context, schedule, index + 1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerRow(BuildContext context, ScoutShiftSchedule schedule) {
    return Row(
      children: [
        _cornerCell(context),
        for (var col = 0; col < schedule.roster.length; col++)
          _HeaderCell(
            key: ValueKey('scout-shift-header-$col'),
            name: schedule.roster[col].name,
            editable: widget.canEdit,
            onTap: () => _renameColumn(col),
          ),
      ],
    );
  }

  Widget _matchRow(
    BuildContext context,
    ScoutShiftSchedule schedule,
    int match,
  ) {
    return Row(
      children: [
        _MatchNumberCell(match: match),
        for (var col = 0; col < schedule.roster.length; col++)
          _DataCell(
            key: ValueKey('scout-shift-cell-$col-$match'),
            color: schedule.colorFor(col, match),
            text: schedule.textFor(col, match),
            editable: widget.canEdit,
            selected: _selectedCells.contains((col, match)),
            onTap: () => _editCell(col, match),
          ),
      ],
    );
  }

  Widget _cornerCell(BuildContext context) {
    return SizedBox(
      width: ScoutShiftGrid.numberColumnWidth,
      height: ScoutShiftGrid.rowHeight,
      child: Center(
        child: Text(
          'names',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _MatchNumberCell extends StatelessWidget {
  const _MatchNumberCell({required this.match});

  final int match;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ScoutShiftGrid.numberColumnWidth,
      height: ScoutShiftGrid.rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
      ),
      child: Text(
        '$match',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.name,
    required this.editable,
    required this.onTap,
    super.key,
  });

  final String name;
  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: editable ? onTap : null,
      child: Container(
        width: ScoutShiftGrid.nameColumnWidth,
        height: ScoutShiftGrid.rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: StrategyPalette.surfaceStrongOf(context),
          border: Border.all(color: StrategyPalette.borderOf(context)),
        ),
        child: Text(
          name.isEmpty ? '(no name)' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    required this.color,
    required this.text,
    required this.editable,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final ScheduleCellColor color;
  final String text;
  final bool editable;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: editable ? onTap : null,
      child: Container(
        width: ScoutShiftGrid.nameColumnWidth,
        height: ScoutShiftGrid.rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cellFillOf(context, color),
          border: Border.all(
            color: selected
                ? StrategyPalette.chipSelectedOf(context)
                : StrategyPalette.borderOf(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cellInkOf(context, color)),
        ),
      ),
    );
  }
}

Color cellFillOf(BuildContext context, ScheduleCellColor color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (color) {
    case ScheduleCellColor.green:
      return dark
          ? StrategyPalette.darkScheduleGreen
          : StrategyPalette.scheduleGreen;
    case ScheduleCellColor.white:
      return StrategyPalette.surfaceOf(context);
    case ScheduleCellColor.grey:
      return StrategyPalette.surfaceStrongOf(context);
    case ScheduleCellColor.red:
      return dark ? StrategyPalette.darkError : StrategyPalette.error;
  }
}

Color cellInkOf(BuildContext context, ScheduleCellColor color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (color) {
    case ScheduleCellColor.green:
      return dark
          ? StrategyPalette.darkOnScheduleGreen
          : StrategyPalette.onScheduleGreen;
    case ScheduleCellColor.white:
    case ScheduleCellColor.grey:
      return dark ? StrategyPalette.darkText : StrategyPalette.textPrimary;
    case ScheduleCellColor.red:
      return dark ? StrategyPalette.darkOnError : StrategyPalette.onError;
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return TextField(controller: _controller, autofocus: true);
  }
}

class _CellEditResult {
  const _CellEditResult({required this.text, required this.color});
  final String text;
  final ScheduleCellColor? color;
}

class _CellEditDialog extends StatefulWidget {
  const _CellEditDialog({
    super.key,
    required this.initialText,
    required this.initialColor,
  });

  final String initialText;
  final ScheduleCellColor initialColor;

  @override
  State<_CellEditDialog> createState() => _CellEditDialogState();
}

class _CellEditDialogState extends State<_CellEditDialog> {
  late final TextEditingController _textController = TextEditingController(
    text: widget.initialText,
  );

  late ScheduleCellColor? _color = widget.initialColor;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void submit() => Navigator.of(context)
      .pop(_CellEditResult(text: _textController.text.trim(), color: _color));

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _textController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Text or number'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final color in ScheduleCellColor.values)
              ChoiceChip(
                label: Text(color.name),
                selected: _color == color,
                avatar: CircleAvatar(
                  backgroundColor: cellFillOf(context, color),
                  radius: 8,
                ),
                onSelected: (_) => setState(() => _color = color),
              ),
            ChoiceChip(
              label: const Text('Default'),
              selected: _color == null,
              onSelected: (_) => setState(() => _color = null),
            ),
          ],
        ),
      ],
    );
  }
}
