import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/services/entry_flags.dart';
import '../scouting/services/entry_match.dart';
import '../scouting/services/scout_field_display.dart';
import '../scouting/services/scouting_sync_service.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../scouting/ui/scout_qr_scan_screen.dart';
import '../scouting/widgets/scout_drawing_canvas.dart';
import '../services/assistant/assistant_service.dart';
import '../services/statbotics/team_history_service.dart';
import '../services/scouting_coverage.dart';
import '../state/cycle_log_controller.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_flag_badge.dart';
import '../widgets/scouting_coverage_view.dart';
import '../widgets/segment_label.dart';
import 'analysis_view.dart';

enum _DbView { rows, table, analysis, coverage }

class DatabaseTab extends StatefulWidget {
  const DatabaseTab({
    required this.scoutingController,
    required this.configController,
    required this.canEditAnyEntry,
    required this.canAddManualEntry,
    required this.eventController,
    this.currentUserUid,
    this.cycleLogController,
    this.assistant,
    this.teamHistory,
    this.canPublishSummaries = false,
    this.pitScoutingController,
    this.pitScoutConfigController,
    super.key,
  });

  final ScoutingController scoutingController;
  final CycleLogController? cycleLogController;

  final EventController eventController;

  final ScoutConfigController configController;

  final bool canEditAnyEntry;

  final String? currentUserUid;

  final bool canAddManualEntry;

  final AssistantService? assistant;

  final TeamHistoryService? teamHistory;

  final bool canPublishSummaries;

  final PitScoutingController? pitScoutingController;
  final PitScoutConfigController? pitScoutConfigController;

  @override
  State<DatabaseTab> createState() => _DatabaseTabState();
}

int? matchNumberOf(String matchId) => parseMatchLabel(matchId)?.number;

const List<String> teamNumberFieldCodes = [
  'pTnumber',
  'teamNumber',
  'team',
  'teamNum',
];

int? teamNumberFromFieldValues(Map<String, dynamic> values) {
  for (final code in teamNumberFieldCodes) {
    final v = values[code];
    if (v == null) continue;
    final n = v is num ? v.toInt() : int.tryParse(v.toString());
    if (n != null && n > 0) return n;
  }
  return null;
}

String? teamNumberFieldCodeOf(ScoutConfig config) {
  final codes = {for (final f in config.allFields) f.code};
  for (final candidate in teamNumberFieldCodes) {
    if (codes.contains(candidate)) return candidate;
  }
  return null;
}

String? stationFieldCodeOf(ScoutConfig config) {
  for (final field in config.allFields) {
    if (field.type != ScoutFieldType.select) continue;
    final choices = field.choices;
    if (choices == null) continue;
    if (choices.keys.any((k) => allianceFromStationValue(k) != null)) {
      return field.code;
    }
  }
  return null;
}

enum EntryOrder { spreadsheet, newestFirst, submitted }

String entryOrderLabel(EntryOrder order) => switch (order) {
  EntryOrder.spreadsheet => 'Match 1 first',
  EntryOrder.newestFirst => 'Newest first',
  EntryOrder.submitted => 'Submitted first',
};

int compareEntriesByMatch(
  ScoutEntry a,
  ScoutEntry b, [
  EntryOrder order = EntryOrder.spreadsheet,
]) {
  if (order == EntryOrder.submitted) {
    final byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.teamNumber.compareTo(b.teamNumber);
  }
  final aNumber = matchNumberOfEntry(a);
  final bNumber = matchNumberOfEntry(b);

  if (aNumber == null && bNumber != null) return 1;
  if (aNumber != null && bNumber == null) return -1;
  final descending = order == EntryOrder.newestFirst;
  if (aNumber != null && bNumber != null && aNumber != bNumber) {
    return descending ? bNumber.compareTo(aNumber) : aNumber.compareTo(bNumber);
  }
  final byId = matchGroupKeyOfEntry(a).compareTo(matchGroupKeyOfEntry(b));
  if (byId != 0) return descending ? -byId : byId;

  final byCreated = a.createdAt.compareTo(b.createdAt);
  if (byCreated != 0) return descending ? -byCreated : byCreated;

  return a.teamNumber.compareTo(b.teamNumber);
}

class _MatchGroupHeader {
  const _MatchGroupHeader({required this.title, required this.count});

  final String title;
  final int count;
}

class _DatabaseTabState extends State<DatabaseTab> {
  final TextEditingController _teamFilter = TextEditingController();
  final TextEditingController _matchFilter = TextEditingController();
  bool _isRefreshing = false;
  _DbView _view = _DbView.table;
  EntryOrder _order = EntryOrder.spreadsheet;
  final Map<String, double> _columnWidths = {};

  static const String _orderPrefsKey = 'database_entry_order';

  int _memoRevision = -1;
  String _memoTeamText = '';
  String _memoMatchText = '';
  EntryOrder _memoOrder = EntryOrder.spreadsheet;
  bool _memoWantsFlags = false;
  List<StatboticsMatch>? _memoScheduleSource;
  List<ScoutEntry> _memoFiltered = const <ScoutEntry>[];
  List<Object> _memoGrouped = const <Object>[];
  EntryFlags _memoFlags = const EntryFlags.empty();

  void _refreshDerived(List<ScoutEntry> all, bool wantsFlags) {
    final revision = widget.scoutingController.entriesRevision;
    final teamText = _teamFilter.text.trim();
    final matchText = _matchFilter.text.trim();
    final scheduleSource = widget.eventController.matches;

    final sameFilterInputs =
        revision == _memoRevision &&
        teamText == _memoTeamText &&
        matchText == _memoMatchText &&
        _order == _memoOrder;
    if (!sameFilterInputs) {
      _memoFiltered = _filtered(all);
      _memoGrouped = _grouped(_memoFiltered);
    }

    if (!wantsFlags) {
      _memoFlags = const EntryFlags.empty();
    } else if (revision != _memoRevision ||
        !identical(scheduleSource, _memoScheduleSource) ||
        !_memoWantsFlags) {
      _memoFlags = EntryFlags.detect(
        all,
        scheduledMatchNumbers: <int>[
          for (final match in scheduleSource)
            if (match.compLevel == 'qm') match.matchNumber,
        ],
      );
    }

    _memoRevision = revision;
    _memoTeamText = teamText;
    _memoMatchText = matchText;
    _memoOrder = _order;
    _memoScheduleSource = scheduleSource;
    _memoWantsFlags = wantsFlags;
  }

  @override
  void initState() {
    super.initState();
    _restoreOrder();
  }

  Future<void> _restoreOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_orderPrefsKey);
      if (stored == null || !mounted) return;
      final restored = EntryOrder.values
          .where((EntryOrder value) => value.name == stored)
          .firstOrNull;
      if (restored == null || restored == _order) return;
      setState(() => _order = restored);
    } catch (_) {}
  }

  Future<void> _setOrder(EntryOrder order) async {
    if (order == _order) return;
    setState(() => _order = order);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_orderPrefsKey, order.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _teamFilter.dispose();
    _matchFilter.dispose();
    super.dispose();
  }

  List<ScoutEntry> _filtered(List<ScoutEntry> all) {
    final teamText = _teamFilter.text.trim();
    final matchText = _matchFilter.text.trim();
    return all
        .where((entry) {
          if (teamText.isNotEmpty) {
            final n = int.tryParse(teamText);
            if (n != null && entry.teamNumber != n) return false;
          }
          if (matchText.isNotEmpty) {
            final haystack =
                '${matchLabelOfEntry(entry)} ${matchGroupKeyOfEntry(entry)}'
                    .toLowerCase();
            if (!haystack.contains(matchText.toLowerCase())) return false;
          }
          return true;
        })
        .toList(growable: false)
      ..sort(
        (ScoutEntry a, ScoutEntry b) => compareEntriesByMatch(a, b, _order),
      );
  }

  List<Object> _grouped(List<ScoutEntry> sorted) {
    final items = <Object>[];
    var start = 0;
    for (var i = 0; i <= sorted.length; i++) {
      final boundary =
          i == sorted.length ||
          matchGroupKeyOfEntry(sorted[i]) !=
              matchGroupKeyOfEntry(sorted[start]);
      if (!boundary) continue;
      if (i > start) {
        items.add(
          _MatchGroupHeader(
            title: matchLabelOfEntry(sorted[start]),
            count: i - start,
          ),
        );
        items.addAll(sorted.sublist(start, i));
      }
      start = i;
    }
    return items;
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await widget.scoutingController.syncNow();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  double _colWidth(String key, {double d = 100}) =>
      _columnWidths.putIfAbsent(key, () => d);

  bool _canEditEntry(ScoutEntry entry) =>
      widget.canEditAnyEntry ||
      (widget.currentUserUid != null &&
          widget.currentUserUid!.isNotEmpty &&
          entry.authorUid == widget.currentUserUid);

  static bool _showsFlags(_DbView view) =>
      view == _DbView.table || view == _DbView.rows;

  Color? _rowColor(
    BuildContext context,
    ScoutEntry entry,
    EntryFlags flags,
    int band,
  ) {
    final worst = flags.worstFor(entry);
    if (worst != null) {
      return entryFlagTint(context, worst.kind);
    }
    if (band.isOdd) {
      return StrategyPalette.surfaceStrongOf(context);
    }
    return null;
  }

  Map<String, int> _matchBands(List<ScoutEntry> entries) {
    final bands = <String, int>{};
    var band = 0;
    String? previousKey;
    for (final entry in entries) {
      final key = matchGroupKeyOfEntry(entry);
      if (previousKey != null && key != previousKey) band++;
      previousKey = key;
      bands[entry.id] = band;
    }
    return bands;
  }

  Widget _resizableHeader(String label, String key) {
    final w = _colWidth(key);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: w,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            setState(() {
              _columnWidths[key] = (_colWidth(key) + d.delta.dx)
                  .clamp(60, 400)
                  .toDouble();
            });
          },
          child: const MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: SizedBox(
              width: 12,
              height: 40,
              child: Align(
                alignment: Alignment.centerRight,
                child: VerticalDivider(width: 1, thickness: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _scanIntoNewEntry() async {
    final messenger = ScaffoldMessenger.of(context);
    final entry = await Navigator.of(context).push<ScoutEntry>(
      MaterialPageRoute<ScoutEntry>(
        builder: (_) => ScoutQrScanScreen(
          controller: widget.scoutingController,
          config: widget.configController.config,
        ),
      ),
    );
    if (!mounted || entry == null) return;
    final teamLabel = entry.teamNumber > 0
        ? ' for team ${entry.teamNumber}'
        : '';
    messenger.showSnackBar(
      SnackBar(content: Text('Imported entry$teamLabel from QR.')),
    );
  }

  void _openAddEntryDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _AddEntryDialog(
        controller: widget.scoutingController,
        configController: widget.configController,
      ),
    );
  }

  String _cellText(ScoutEntry entry, String key, ScoutConfigField? field) {
    final stored = entry.fieldValues[key];
    if (stored == null &&
        teamNumberFieldCodes.contains(key) &&
        entry.teamNumber > 0) {
      return entry.teamNumber.toString();
    }
    return displayFieldValue(field, stored);
  }

  static const double _resizeHandleWidth = 12;
  static const double _headerRowHeight = 40;
  static const double _dataRowHeight = 44;

  static const double _tableHorizontalInset = 16;

  String _tableColumnLabel(String key, ScoutConfigField? field) =>
      switch (key) {
        '__check__' => 'Check',
        '__author__' => 'Author',
        '__notes__' => 'Notes',
        _ => field?.title ?? key,
      };

  Widget _tableCellContent(
    ScoutEntry entry,
    String key,
    ScoutConfigField? field,
    EntryFlags flags,
  ) {
    switch (key) {
      case '__check__':
        return EntryFlagBadge(flags: flags.forEntry(entry));
      case '__author__':
        return Row(
          children: [
            Expanded(
              child: Text(
                entry.authorDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.addedManually) ...[
              const SizedBox(width: 4),
              manualEntryIndicator(context, compact: true),
            ],
          ],
        );
      case '__notes__':
        return Text(entry.notes, maxLines: 1, overflow: TextOverflow.ellipsis);
      default:
        return Text(_cellText(entry, key, field));
    }
  }

  VoidCallback? _tableCellTap(
    ScoutEntry entry,
    String key,
    ScoutConfigField? field,
  ) {
    if (key == '__check__' || !_canEditEntry(entry)) return null;
    return switch (key) {
      '__author__' => () => _editEntryCell(
        context,
        entry,
        _EntryFieldKind.author,
      ),
      '__notes__' => () => _editEntryCell(
        context,
        entry,
        _EntryFieldKind.notes,
      ),
      _ => () => _editTableCell(context, entry, key, field),
    };
  }

  Widget _buildTableView(List<ScoutEntry> entries, EntryFlags flags) {
    final config = widget.configController.config;
    final allFields = config.allFields;
    final fieldByCode = {for (final f in allFields) f.code: f};

    final allKeys = <String>{};
    for (final e in entries) {
      allKeys.addAll(e.fieldValues.keys);
    }

    final configOrder = [for (final f in allFields) f.code];
    final orderedKeys = [
      for (final code in configOrder)
        if (allKeys.contains(code)) code,
    ];

    final unknownKeys = allKeys.difference(orderedKeys.toSet()).toList()
      ..sort();
    final sortedKeys = [...orderedKeys, ...unknownKeys];

    final hasFlags = entries.any(
      (ScoutEntry entry) => flags.forEntry(entry).isNotEmpty,
    );
    final bands = _matchBands(entries);

    final columnKeys = <String>[
      if (hasFlags) '__check__',
      ...sortedKeys,
      '__author__',
      '__notes__',
    ];

    final table = TableView.builder(
      pinnedRowCount: 1,
      columnCount: columnKeys.length,
      rowCount: entries.length + 1,
      columnBuilder: (int column) {
        final width = _colWidth(columnKeys[column]) + _resizeHandleWidth;
        final extent = FixedTableSpanExtent(width);
        if (column < columnKeys.length - 1) {
          return TableSpan(extent: extent);
        }

        return TableSpan(
          extent: MaxTableSpanExtent(extent, const RemainingTableSpanExtent()),
        );
      },
      rowBuilder: (int row) {
        return TableSpan(
          extent: FixedTableSpanExtent(
            row == 0 ? _headerRowHeight : _dataRowHeight,
          ),
        );
      },
      cellBuilder: (BuildContext context, TableVicinity vicinity) {
        final key = columnKeys[vicinity.column];
        if (vicinity.row == 0) {
          return TableViewCell(
            child: _resizableHeader(
              _tableColumnLabel(key, fieldByCode[key]),
              key,
            ),
          );
        }
        final entry = entries[vicinity.row - 1];
        final field = fieldByCode[key];
        final fill = _rowColor(context, entry, flags, bands[entry.id] ?? 0);
        final content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _tableCellContent(entry, key, field, flags),
          ),
        );
        final tinted = fill == null
            ? content
            : DatabaseRowFill(color: fill, child: content);
        final onTap = _tableCellTap(entry, key, field);
        return TableViewCell(
          child: onTap == null
              ? tinted
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: tinted,
                ),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _tableHorizontalInset),
      child: table,
    );
  }

  void _editTableCell(
    BuildContext context,
    ScoutEntry entry,
    String fieldCode,
    ScoutConfigField? field,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _FieldEditDialog(
          entry: entry,
          field: field,
          fieldCode: fieldCode,
          controller: widget.scoutingController,
        );
      },
    );
  }

  void _editEntryCell(
    BuildContext context,
    ScoutEntry entry,
    _EntryFieldKind kind,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return _EntryFieldEditDialog(
          entry: entry,
          controller: widget.scoutingController,
          kind: kind,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.scoutingController,
        widget.configController,
        widget.eventController,
      ]),
      builder: (context, _) {
        final all = widget.scoutingController.entries;
        final syncStatus = widget.scoutingController.syncStatus;

        _refreshDerived(all, _showsFlags(_view));
        final filtered = _memoFiltered;
        final grouped = _memoGrouped;
        final flags = _memoFlags;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              _FilterBar(
                order: _order,
                onOrderChanged: _setOrder,
                teamFilter: _teamFilter,
                matchFilter: _matchFilter,
                syncStatus: syncStatus,
                isRefreshing: _isRefreshing,
                onRefresh: _refresh,
                onScan: _scanIntoNewEntry,
                onAddEntry: widget.canAddManualEntry
                    ? _openAddEntryDialog
                    : null,
                onFilterChanged: () => setState(() {}),
                view: _view,
                onViewChanged: (v) => setState(() => _view = v),
                showMatchFilter:
                    _view != _DbView.analysis && _view != _DbView.coverage,
              ),
              Expanded(
                child: switch (_view) {
                  _DbView.table => _buildTableView(filtered, flags),
                  _DbView.rows =>
                    filtered.isEmpty
                        ? _EmptyState(
                            hasEntries: all.isNotEmpty,
                            syncState: syncStatus.state,
                          )
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 720,
                                ),
                                child: ListView.builder(
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    16,
                                  ),
                                  itemCount: grouped.length,
                                  itemBuilder: (context, index) {
                                    final item = grouped[index];
                                    if (item is _MatchGroupHeader) {
                                      return _MatchGroupHeaderRow(header: item);
                                    }
                                    final entry = item as ScoutEntry;
                                    return _EntryCard(
                                      entry: entry,
                                      flags: flags.forEntry(entry),
                                      controller: widget.scoutingController,
                                      configController: widget.configController,
                                      canEdit: _canEditEntry(entry),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                  _DbView.coverage => ScoutingCoverageView(
                    coverage: ScoutingCoverage.build(
                      schedule: widget.eventController.matches,
                      entries: all,
                    ),
                    hasEvent: widget.eventController.eventKey.isNotEmpty,
                  ),
                  _DbView.analysis => AnalysisView(
                    controller: widget.scoutingController,
                    configController: widget.configController,
                    cycleLogController: widget.cycleLogController,
                    teamFilter: int.tryParse(_teamFilter.text.trim()),
                    assistant: widget.assistant,
                    teamHistory: widget.teamHistory,
                    canPublishSummaries: widget.canPublishSummaries,
                    eventKey: widget.eventController.eventKey,
                    pitScoutingController: widget.pitScoutingController,
                    pitScoutConfigController: widget.pitScoutConfigController,
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.order,
    required this.onOrderChanged,
    required this.teamFilter,
    required this.matchFilter,
    required this.syncStatus,
    required this.isRefreshing,
    required this.onRefresh,
    this.onScan,
    this.onAddEntry,
    required this.onFilterChanged,
    required this.view,
    required this.onViewChanged,
    required this.showMatchFilter,
  });

  final EntryOrder order;
  final ValueChanged<EntryOrder> onOrderChanged;

  final TextEditingController teamFilter;
  final TextEditingController matchFilter;
  final ScoutingSyncStatus syncStatus;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  final VoidCallback? onScan;

  final VoidCallback? onAddEntry;
  final VoidCallback onFilterChanged;
  final _DbView view;
  final ValueChanged<_DbView> onViewChanged;
  final bool showMatchFilter;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: StrategyPalette.surfaceOf(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),

            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final compactSwitcher =
                    constraints.maxWidth < _iconlessSwitcherBreakpoint;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _viewSwitcher(showIcons: !compactSwitcher),
                        if (_showsOrderControl(view)) _orderControl(context),
                        if (onScan != null)
                          OutlinedButton.icon(
                            onPressed: onScan,
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 18,
                            ),
                            label: const Text('Scan'),
                          ),
                        if (onAddEntry != null)
                          OutlinedButton.icon(
                            onPressed: onAddEntry,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add entry'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildFilterRow(context),
                    const SizedBox(height: 6),
                    _SyncStatusRow(status: syncStatus),
                  ],
                );
              },
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: StrategyPalette.borderOf(context),
          ),
        ],
      ),
    );
  }

  static bool _showsOrderControl(_DbView view) =>
      view == _DbView.rows || view == _DbView.table;

  Widget _orderControl(BuildContext context) {
    return PopupMenuButton<EntryOrder>(
      tooltip: 'Row order',
      initialValue: order,
      onSelected: onOrderChanged,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<EntryOrder>>[
        for (final EntryOrder value in EntryOrder.values)
          PopupMenuItem<EntryOrder>(
            value: value,
            child: Text(entryOrderLabel(value)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),

        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.swap_vert_rounded, size: 18),
                ),
              ),
              TextSpan(text: entryOrderLabel(order)),
            ],
          ),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }

  static const double _iconlessSwitcherBreakpoint = 420;

  static const EdgeInsets _compactSegmentPadding = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 10,
  );

  Widget _viewSwitcher({required bool showIcons}) {
    return SegmentedButton<_DbView>(
      style: showIcons
          ? null
          : SegmentedButton.styleFrom(padding: _compactSegmentPadding),
      segments: [
        ButtonSegment(
          value: _DbView.table,
          label: const SegmentLabel('Table'),
          icon: showIcons ? const Icon(Icons.view_column_outlined) : null,
        ),
        ButtonSegment(
          value: _DbView.rows,
          label: const SegmentLabel('Rows'),
          icon: showIcons ? const Icon(Icons.table_rows_outlined) : null,
        ),
        ButtonSegment(
          value: _DbView.analysis,
          label: const SegmentLabel('Analysis'),
          icon: showIcons ? const Icon(Icons.insights_outlined) : null,
        ),
        ButtonSegment(
          value: _DbView.coverage,
          label: const SegmentLabel('Coverage'),
          icon: showIcons ? const Icon(Icons.grid_view_outlined) : null,
        ),
      ],
      selected: {view},
      onSelectionChanged: (s) => onViewChanged(s.first),
      showSelectedIcon: false,
    );
  }

  static const double _narrowFilterBreakpoint = 600;

  Widget _buildFilterRow(BuildContext context) {
    final teamField = TextField(
      controller: teamFilter,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Filter by team',
        prefixIcon: Icon(Icons.group_outlined, size: 18),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onChanged: (_) => onFilterChanged(),
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
    );
    final matchField = TextField(
      controller: matchFilter,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Filter by match',
        prefixIcon: Icon(Icons.tag_rounded, size: 18),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onChanged: (_) => onFilterChanged(),
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
    );
    final refreshButton = IconButton(
      icon: isRefreshing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
      tooltip: 'Refresh from database',
      onPressed: isRefreshing ? null : onRefresh,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _narrowFilterBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: teamField),
                  const SizedBox(width: 8),
                  refreshButton,
                ],
              ),
              if (showMatchFilter) ...[const SizedBox(height: 8), matchField],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: teamField),
            if (showMatchFilter) ...[
              const SizedBox(width: 8),
              Expanded(child: matchField),
            ],
            const SizedBox(width: 8),
            refreshButton,
          ],
        );
      },
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  const _SyncStatusRow({required this.status});

  final ScoutingSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (String label, IconData icon, Color color) = switch (status.state) {
      ScoutingSyncState.signedOut => (
        'Sign in to load the team database',
        Icons.cloud_off_rounded,
        colorScheme.error,
      ),
      ScoutingSyncState.noAccess => (
        'No team access yet. Ask an admin to approve your account.',
        Icons.lock_outline_rounded,
        colorScheme.error,
      ),
      ScoutingSyncState.syncing => (
        'Syncing...',
        Icons.sync_rounded,
        colorScheme.primary,
      ),
      ScoutingSyncState.synced => (
        status.lastSyncedAt != null
            ? 'Last synced ${_formatTime(status.lastSyncedAt!)}'
            : 'Synced',
        Icons.cloud_done_rounded,
        colorScheme.primary,
      ),
      ScoutingSyncState.offline => (
        'Offline — showing cached entries',
        Icons.cloud_off_rounded,
        colorScheme.onSurfaceVariant,
      ),
    };

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ),
        if (status.pendingWrites > 0) ...[
          const SizedBox(width: 8),
          Icon(Icons.cloud_upload_outlined, size: 14, color: colorScheme.error),
          const SizedBox(width: 4),
          Text(
            '${status.pendingWrites} pending',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return 'at $h:$m';
  }
}

class _MatchGroupHeaderRow extends StatelessWidget {
  const _MatchGroupHeaderRow({required this.header});

  final _MatchGroupHeader header;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Text(
            header.title,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: colorScheme.outline)),
          const SizedBox(width: 12),
          Text(
            header.count == 1 ? '1 entry' : '${header.count} entries',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.flags,
    required this.controller,
    required this.configController,
    required this.canEdit,
  });

  final ScoutEntry entry;

  final List<EntryFlag> flags;

  final ScoutingController controller;
  final ScoutConfigController configController;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (avatarFill, avatarInk) = _allianceColors(
      context,
      entry.effectiveAlliance,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),

      color: flags.isEmpty ? null : entryFlagTint(context, flags.first.kind),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: avatarFill,
          child: Text(
            entry.teamNumber > 0 ? entry.teamNumber.toString() : '?',
            style: TextStyle(
              color: avatarInk,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        title: Text(
          entry.teamNumber > 0 ? 'Team ${entry.teamNumber}' : 'Unknown team',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),

        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (flags.isNotEmpty) ...[
              const SizedBox(height: 4),
              EntryFlagBadge(flags: flags),
            ],
            if (entry.addedManually) ...[
              const SizedBox(height: 4),
              manualEntryIndicator(context),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                _InfoRow(label: 'Match', value: entry.matchId),
                _InfoRow(label: 'Alliance', value: entry.effectiveAlliance),
                if (entry.authorDisplayName.isNotEmpty)
                  _InfoRow(label: 'Scouted by', value: entry.authorDisplayName),
                if (entry.addedManually)
                  const _InfoRow(
                    label: 'Source',
                    value: 'Added manually, not scouted',
                  ),
                _InfoRow(
                  label: 'Last updated',
                  value: _formatDateTime(entry.updatedAt.toLocal()),
                ),
                if (entry.fieldValues.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Field values',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  ...entry.fieldValues.entries.map(
                    (kv) => _InfoRow(
                      label: kv.key,
                      value: kv.value?.toString() ?? '',
                    ),
                  ),
                ],
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Notes',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (entry.strokesByPhase != null &&
                    entry.strokesByPhase!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  ReadOnlyDrawingPreview(strokesByPhase: entry.strokesByPhase),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _openEditDialog(context),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit entry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openEditDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _EditEntryDialog(
        entry: entry,
        controller: controller,
        configController: configController,
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[entry.effectiveAlliance];
    if (entry.fieldValues.isNotEmpty) {
      parts.add('${entry.fieldValues.length} fields');
    }
    return parts.join(' · ');
  }

  String _formatDateTime(DateTime dt) {
    final d = '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
    final t = '${_pad(dt.hour)}:${_pad(dt.minute)}';
    return '$d $t';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class DatabaseRowFill extends StatelessWidget {
  const DatabaseRowFill({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: color, child: child);
}

Widget manualEntryIndicator(BuildContext context, {bool compact = false}) {
  final colorScheme = Theme.of(context).colorScheme;
  const message =
      'Added manually from the Database tab, not submitted by a '
      'scouter.';
  final icon = Icon(
    Icons.edit_note_rounded,
    size: 14,
    color: colorScheme.onSurfaceVariant,
  );
  if (compact) {
    return Tooltip(message: message, child: icon);
  }
  return Tooltip(
    message: message,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceStrongOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            'Manual',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

ScoutConfigField? _fieldOfType(
  List<ScoutConfigField> fields,
  ScoutFieldType type,
) {
  for (final field in fields) {
    if (field.type == type) return field;
  }
  return null;
}

Widget scoutSelectEditor({
  required ScoutConfigField field,
  required dynamic value,
  required ValueChanged<String> onChanged,
}) {
  final choices = field.choices;
  if (choices == null || choices.isEmpty) {
    return const Text('No choices configured.');
  }
  final currentValue = value?.toString() ?? '';

  final validValue =
      field.resolveStoredChoice(currentValue) ??
      field.activeChoices.keys.firstOrNull ??
      '';

  final options = field.choiceOptions(
    validValue.isEmpty ? const <String>[] : <String>[validValue],
  );
  return DropdownButtonFormField<String>(
    initialValue: validValue.isEmpty ? null : validValue,
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },

    items: <DropdownMenuItem<String>>[
      for (final e in options.entries)
        DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
    ],
  );
}

Widget scoutCheckboxSelectEditor({
  required ScoutConfigField field,
  required dynamic value,
  required ValueChanged<String> onChanged,
}) {
  final choices = field.choices;
  if (choices == null || choices.isEmpty) {
    return const Text('No choices configured.');
  }
  final selected = ScoutConfigField.selectedKeys(value);

  final options = field.choiceOptions(selected);
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in options.entries)
        FilterChip(
          label: Text(entry.value),
          selected: selected.contains(entry.key),
          onSelected: (on) {
            final next = <String>[
              for (final key in options.keys)
                if (key == entry.key ? on : selected.contains(key)) key,
            ];
            onChanged(ScoutConfigField.joinKeys(next));
          },
        ),
    ],
  );
}

Widget scoutRangeEditor({
  required BuildContext context,
  required ScoutConfigField field,
  required dynamic value,
  required ValueChanged<double> onChanged,
}) {
  final min = field.min ?? 0;
  final max = field.max ?? 100;
  final step = field.step ?? 1;
  final doubleValue = (value is num) ? value.toDouble().clamp(min, max) : min;
  return Column(
    children: [
      Slider(
        value: doubleValue,
        min: min,
        max: max,
        divisions: () {
          if (step <= 0) return null;
          final d = ((max - min) / step).round();
          return d > 0 ? d : null;
        }(),
        label: doubleValue.toStringAsFixed(step < 1 ? 1 : 0),
        onChanged: onChanged,
      ),
      Text(
        '${doubleValue.toStringAsFixed(step < 1 ? 1 : 0)} / ${max.toStringAsFixed(0)}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

Widget scoutCounterEditor({
  required BuildContext context,
  required ScoutConfigField field,
  required dynamic value,
  required ValueChanged<int> onChanged,
}) {
  final intValue = (value is num) ? value.toInt() : 0;
  final steps = (field.buttons == null || field.buttons!.isEmpty)
      ? const <int>[1]
      : field.buttons!;
  final effectiveMin = field.min?.toInt() ?? 0;
  final effectiveMax = field.max?.toInt();

  return Column(
    children: [
      Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                onPressed: intValue - steps[i] < effectiveMin
                    ? null
                    : () => onChanged(intValue - steps[i]),
                child: Text('-${steps[i]}'),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Text(
        intValue.toString(),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                onPressed:
                    effectiveMax != null && intValue + steps[i] > effectiveMax
                    ? null
                    : () => onChanged(intValue + steps[i]),
                child: Text('+${steps[i]}'),
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({
    required this.entry,
    required this.controller,
    required this.configController,
  });

  final ScoutEntry entry;
  final ScoutingController controller;
  final ScoutConfigController configController;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  late final TextEditingController _notesCtrl;
  final _fieldValues = <String, dynamic>{};
  final _textControllers = <String, TextEditingController>{};
  List<ScoutConfigField> _configFields = const [];
  List<String> _extraKeys = const [];

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.entry.notes);
    _fieldValues.addAll(widget.entry.fieldValues);

    final config = widget.configController.config;
    _configFields = config.allFields;
    final configCodes = _configFields.map((f) => f.code).toSet();
    _extraKeys =
        widget.entry.fieldValues.keys
            .where((k) => !configCodes.contains(k))
            .toList()
          ..sort();

    for (final field in _configFields) {
      if (field.type == ScoutFieldType.text ||
          field.type == ScoutFieldType.number ||
          field.type == ScoutFieldType.tbaMatchNumber) {
        final value = _fieldValues[field.code] ?? field.effectiveDefault;
        _textControllers[field.code] = TextEditingController(
          text: value.toString(),
        );
      }
    }
    for (final key in _extraKeys) {
      _textControllers[key] = TextEditingController(
        text: _fieldValues[key]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    final merged = Map<String, dynamic>.from(_fieldValues);
    for (final field in _configFields) {
      if (field.type == ScoutFieldType.text ||
          field.type == ScoutFieldType.number ||
          field.type == ScoutFieldType.tbaMatchNumber) {
        final raw = _textControllers[field.code]?.text ?? '';

        if (field.type != ScoutFieldType.text) {
          final parsed = num.tryParse(raw.trim());
          if (parsed != null) {
            merged[field.code] = parsed;
          } else if (raw.trim().isEmpty) {
            merged.remove(field.code);
          }
        } else {
          merged[field.code] = raw;
        }
      }
    }
    for (final key in _extraKeys) {
      final raw = _textControllers[key]?.text ?? '';
      final original = widget.entry.fieldValues[key];
      if (raw == original?.toString()) continue;
      merged[key] = switch (original) {
        bool _ => raw.toLowerCase() == 'true',
        num _ => num.tryParse(raw.trim()) ?? original,
        _ => raw,
      };
    }

    final teamNumber =
        teamNumberFromFieldValues(merged) ?? widget.entry.teamNumber;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.saveEntry(
        widget.entry.copyWith(
          notes: _notesCtrl.text,
          fieldValues: merged,
          teamNumber: teamNumber,
        ),
      );
      if (!mounted) return;
      if (!saved) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.controller.lastError ?? 'Save failed.'),
          ),
        );
        widget.controller.clearLastError();
        return;
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Edit — Team ${widget.entry.teamNumber}, ${widget.entry.matchId}',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _notesCtrl,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              for (final field in _configFields) ...[
                _buildFieldEditor(field),
                const SizedBox(height: 12),
              ],
              if (_extraKeys.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Extra fields',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final key in _extraKeys) ...[
                  TextField(
                    controller: _textControllers[key],
                    decoration: InputDecoration(
                      labelText: key,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildFieldEditor(ScoutConfigField field) {
    final value = _fieldValues[field.code] ?? field.effectiveDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          field.title,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        switch (field.type) {
          ScoutFieldType.actionTracker => Text(
            'Recorded as ${field.code}_*_count and _times below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ScoutFieldType.text => TextField(
            controller: _textControllers[field.code],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          ScoutFieldType.number || ScoutFieldType.tbaMatchNumber => TextField(
            controller: _textControllers[field.code],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          ScoutFieldType.tbaTeamAndRobot => Text(
            'Edited through the entry\'s team number.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ScoutFieldType.boolean => Switch(
            value: value is bool && value,
            onChanged: (v) {
              setState(() => _fieldValues[field.code] = v);
            },
          ),
          ScoutFieldType.select => _buildSelect(field, value),
          ScoutFieldType.checkboxSelect => _buildCheckboxSelect(field, value),
          ScoutFieldType.range => _buildRange(field, value),
          ScoutFieldType.counter ||
          ScoutFieldType.multiCounter => _buildCounter(field, value),
        },
      ],
    );
  }

  Widget _buildCheckboxSelect(ScoutConfigField field, dynamic value) {
    return scoutCheckboxSelectEditor(
      field: field,
      value: value,
      onChanged: (v) => setState(() => _fieldValues[field.code] = v),
    );
  }

  Widget _buildSelect(ScoutConfigField field, dynamic value) {
    return scoutSelectEditor(
      field: field,
      value: value,
      onChanged: (v) => setState(() => _fieldValues[field.code] = v),
    );
  }

  Widget _buildRange(ScoutConfigField field, dynamic value) {
    return scoutRangeEditor(
      context: context,
      field: field,
      value: value,
      onChanged: (v) => setState(() => _fieldValues[field.code] = v),
    );
  }

  Widget _buildCounter(ScoutConfigField field, dynamic value) {
    return scoutCounterEditor(
      context: context,
      field: field,
      value: value,
      onChanged: (v) => setState(() => _fieldValues[field.code] = v),
    );
  }
}

class _AddEntryDialog extends StatefulWidget {
  const _AddEntryDialog({
    required this.controller,
    required this.configController,
  });

  final ScoutingController controller;
  final ScoutConfigController configController;

  @override
  State<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<_AddEntryDialog> {
  static const List<String> _stations = <String>[
    'R1',
    'R2',
    'R3',
    'B1',
    'B2',
    'B3',
  ];

  final _teamCtrl = TextEditingController();
  final _matchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _station = _stations.first;
  final _fieldValues = <String, dynamic>{};
  final _textControllers = <String, TextEditingController>{};
  List<ScoutConfigField> _configFields = const [];

  @override
  void initState() {
    super.initState();

    final config = widget.configController.config;
    final teamCode = teamNumberFieldCodeOf(config);
    final stationCode = stationFieldCodeOf(config);
    _configFields = config.allFields
        .where(
          (f) =>
              f.type != ScoutFieldType.tbaTeamAndRobot &&
              f.type != ScoutFieldType.tbaMatchNumber &&
              f.code != teamCode &&
              f.code != stationCode,
        )
        .toList(growable: false);
    for (final field in _configFields) {
      if (field.type == ScoutFieldType.text ||
          field.type == ScoutFieldType.number) {
        _fieldValues[field.code] = field.effectiveDefault;
        _textControllers[field.code] = TextEditingController(
          text: field.effectiveDefault.toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    _teamCtrl.dispose();
    _matchCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    final team = int.tryParse(_teamCtrl.text.trim());
    if (team == null || team <= 0) {
      setState(() => _error = 'Enter a whole team number.');
      return;
    }
    final matchText = _matchCtrl.text.trim();
    final matchNumber = matchText.isEmpty ? null : num.tryParse(matchText);
    if (matchText.isNotEmpty && matchNumber == null) {
      setState(() => _error = 'Match number must be a number.');
      return;
    }
    setState(() => _error = null);

    final merged = Map<String, dynamic>.from(_fieldValues);
    for (final field in _configFields) {
      if (field.type != ScoutFieldType.text &&
          field.type != ScoutFieldType.number) {
        continue;
      }
      final raw = _textControllers[field.code]?.text ?? '';
      if (field.type == ScoutFieldType.number) {
        final parsed = num.tryParse(raw.trim());
        if (parsed != null) merged[field.code] = parsed;
      } else {
        merged[field.code] = raw;
      }
    }
    if (matchNumber != null) {
      merged['matchNumber'] = matchNumber;
    }
    final teamRobotField = _fieldOfType(
      widget.configController.config.allFields,
      ScoutFieldType.tbaTeamAndRobot,
    );
    if (teamRobotField != null) {
      merged[teamRobotField.code] = <String, dynamic>{
        'teamNumber': team,
        'robotPosition': _station,
      };
    } else {
      merged['station'] = _station;
    }

    final teamCode = teamNumberFieldCodeOf(widget.configController.config);
    if (teamCode != null) merged[teamCode] = team;
    final stationCode = stationFieldCodeOf(widget.configController.config);
    if (stationCode != null) merged[stationCode] = _station;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.saveEntry(
        ScoutEntry(
          matchId: '',
          teamNumber: team,
          alliance: allianceFromStationValue(_station) ?? 'Red',
          notes: _notesCtrl.text,
          fieldValues: merged,
          addedManually: true,
        ),
      );
      if (!mounted) return;
      if (!saved) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.controller.lastError ?? 'Save failed.'),
          ),
        );
        widget.controller.clearLastError();
        return;
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add entry'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'For a match nobody scouted. Marked as added manually so it '
                'stays distinguishable from a scouter\'s submission.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('addEntryTeamField'),
                controller: _teamCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Team number',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('addEntryStationField'),
                initialValue: _station,
                decoration: const InputDecoration(
                  labelText: 'Station',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final s in _stations)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _station = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('addEntryMatchField'),
                controller: _matchCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Match number',
                  helperText: 'e.g. 12, or a playoff match number',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('addEntryNotesField'),
                controller: _notesCtrl,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_configFields.isNotEmpty) const SizedBox(height: 16),
              for (final field in _configFields) ...[
                _buildFieldEditor(field),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildFieldEditor(ScoutConfigField field) {
    final value = _fieldValues[field.code] ?? field.effectiveDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          field.title,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        switch (field.type) {
          ScoutFieldType.actionTracker => Text(
            'Recorded as ${field.code}_*_count and _times below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ScoutFieldType.text => TextField(
            controller: _textControllers[field.code],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          ScoutFieldType.number => TextField(
            controller: _textControllers[field.code],
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          ScoutFieldType.boolean => Switch(
            value: value is bool && value,
            onChanged: (v) => setState(() => _fieldValues[field.code] = v),
          ),
          ScoutFieldType.select => scoutSelectEditor(
            field: field,
            value: value,
            onChanged: (v) => setState(() => _fieldValues[field.code] = v),
          ),
          ScoutFieldType.checkboxSelect => scoutCheckboxSelectEditor(
            field: field,
            value: value,
            onChanged: (v) => setState(() => _fieldValues[field.code] = v),
          ),
          ScoutFieldType.range => scoutRangeEditor(
            context: context,
            field: field,
            value: value,
            onChanged: (v) => setState(() => _fieldValues[field.code] = v),
          ),
          ScoutFieldType.counter ||
          ScoutFieldType.multiCounter => scoutCounterEditor(
            context: context,
            field: field,
            value: value,
            onChanged: (v) => setState(() => _fieldValues[field.code] = v),
          ),

          ScoutFieldType.tbaMatchNumber ||
          ScoutFieldType.tbaTeamAndRobot => const SizedBox.shrink(),
        },
      ],
    );
  }
}

(Color, Color) _allianceColors(BuildContext context, String alliance) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (alliance) {
    'Blue' => (StrategyPalette.allianceBlue, StrategyPalette.onAlliance),
    'Red' => (StrategyPalette.allianceRed, StrategyPalette.onAlliance),
    _ => (colorScheme.surfaceContainerHighest, colorScheme.onSurface),
  };
}

class _FieldEditDialog extends StatefulWidget {
  const _FieldEditDialog({
    required this.entry,
    required this.field,
    required this.fieldCode,
    required this.controller,
  });

  final ScoutEntry entry;
  final ScoutConfigField? field;
  final String fieldCode;
  final ScoutingController controller;

  @override
  State<_FieldEditDialog> createState() => _FieldEditDialogState();
}

class _FieldEditDialogState extends State<_FieldEditDialog> {
  late dynamic _value;
  TextEditingController? _textCtrl;

  @override
  void initState() {
    super.initState();
    _value =
        widget.entry.fieldValues[widget.fieldCode] ??
        widget.field?.effectiveDefault;
    final fType = widget.field?.type ?? ScoutFieldType.text;
    if (fType == ScoutFieldType.text ||
        fType == ScoutFieldType.number ||
        fType == ScoutFieldType.tbaMatchNumber) {
      final text = _value?.toString() ?? '';
      _textCtrl = TextEditingController(text: text);
    } else if (fType == ScoutFieldType.select) {
      final field = widget.field;
      if (field != null) {
        _value =
            field.resolveStoredChoice(_value) ??
            field.activeChoices.keys.firstOrNull ??
            _value;
      }
    }
  }

  @override
  void dispose() {
    _textCtrl?.dispose();
    super.dispose();
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    final fType = widget.field?.type ?? ScoutFieldType.text;
    if (_textCtrl != null) {
      final raw = _textCtrl!.text;
      if (fType == ScoutFieldType.number ||
          fType == ScoutFieldType.tbaMatchNumber) {
        final parsed = num.tryParse(raw.trim());
        final min = widget.field?.min;
        final max = widget.field?.max;

        final outOfRange =
            parsed != null &&
            ((min != null && parsed < min) || (max != null && parsed > max));
        if (parsed == null || outOfRange) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a whole number.')),
          );
          return;
        }
        _value = parsed;
      } else {
        _value = raw;
      }
    }
    final newFieldValues = Map<String, dynamic>.from(widget.entry.fieldValues)
      ..[widget.fieldCode] = _value;

    final teamNumber =
        teamNumberFromFieldValues(newFieldValues) ?? widget.entry.teamNumber;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.saveEntry(
        widget.entry.copyWith(
          fieldValues: newFieldValues,
          teamNumber: teamNumber,
        ),
      );

      if (!mounted) return;
      if (!saved) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.controller.lastError ?? 'Save failed.'),
          ),
        );
        widget.controller.clearLastError();
        return;
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final fType = field?.type ?? ScoutFieldType.text;
    final label = field?.title ?? widget.fieldCode;

    return AlertDialog(
      title: Text(label),
      content: SizedBox(width: 320, child: _buildInput(field, fType)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildInput(ScoutConfigField? field, ScoutFieldType fType) {
    switch (fType) {
      case ScoutFieldType.text:
        return TextField(controller: _textCtrl);
      case ScoutFieldType.number:
        return TextField(
          controller: _textCtrl,
          keyboardType: TextInputType.number,
        );
      case ScoutFieldType.boolean:
        return Switch(
          value: _value is bool && _value,
          onChanged: (v) => setState(() => _value = v),
        );
      case ScoutFieldType.checkboxSelect:
        final choices = field?.choices;
        if (field == null || choices == null || choices.isEmpty) {
          return const Text('No choices configured.');
        }
        final selected = ScoutConfigField.selectedKeys(_value);

        final options = field.choiceOptions(selected);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in options.entries)
              FilterChip(
                label: Text(entry.value),
                selected: selected.contains(entry.key),
                onSelected: (on) {
                  final next = <String>[
                    for (final key in options.keys)
                      if (key == entry.key ? on : selected.contains(key)) key,
                  ];
                  setState(() => _value = ScoutConfigField.joinKeys(next));
                },
              ),
          ],
        );
      case ScoutFieldType.select:
        final choices = field?.choices;
        if (field == null || choices == null || choices.isEmpty) {
          return const Text('No choices configured.');
        }
        final currentValue = _value?.toString() ?? '';

        final validValue =
            field.resolveStoredChoice(currentValue) ??
            field.activeChoices.keys.firstOrNull ??
            '';

        final options = field.choiceOptions(
          validValue.isEmpty ? const <String>[] : <String>[validValue],
        );
        return DropdownButtonFormField<String>(
          initialValue: validValue.isEmpty ? null : validValue,
          onChanged: (v) {
            if (v != null) _value = v;
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: <DropdownMenuItem<String>>[
            for (final e in options.entries)
              DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
          ],
        );
      case ScoutFieldType.range:
        final min = field?.min ?? 0;
        final max = field?.max ?? 100;
        final step = field?.step ?? 1;
        final v = (_value is num ? _value.toDouble() : min).clamp(min, max);
        return Column(
          children: [
            Slider(
              value: v,
              min: min,
              max: max,
              divisions: () {
                if (step <= 0) return null;
                final d = ((max - min) / step).round();
                return d > 0 ? d : null;
              }(),
              label: v.toStringAsFixed(step < 1 ? 1 : 0),
              onChanged: (val) => setState(() => _value = val),
            ),
            Text('${v.toStringAsFixed(step < 1 ? 1 : 0)} / $max'),
          ],
        );
      case ScoutFieldType.actionTracker:
        return Text(
          'Action tracker data is edited through its '
          '${field?.code ?? ''}_*_count and _times fields.',
          style: Theme.of(context).textTheme.bodySmall,
        );
      case ScoutFieldType.tbaMatchNumber:
        return TextField(
          controller: _textCtrl,
          keyboardType: TextInputType.number,
        );
      case ScoutFieldType.tbaTeamAndRobot:
        return Text(
          'Team and station are edited through the entry\'s team number.',
          style: Theme.of(context).textTheme.bodySmall,
        );
      case ScoutFieldType.counter:
      case ScoutFieldType.multiCounter:
        final intValue = (_value is num) ? _value.toInt() : 0;
        final steps =
            (field == null || field.buttons == null || field.buttons!.isEmpty)
            ? const <int>[1]
            : field.buttons!;
        final min = field?.min?.toInt() ?? 0;
        final max = field?.max?.toInt();
        return Column(
          children: [
            Row(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: intValue - steps[i] < min
                          ? null
                          : () => setState(() => _value = intValue - steps[i]),
                      child: Text('-${steps[i]}'),
                    ),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                intValue.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Row(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: max != null && intValue + steps[i] > max
                          ? null
                          : () => setState(() => _value = intValue + steps[i]),
                      child: Text('+${steps[i]}'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
    }
  }
}

enum _EntryFieldKind { author, notes }

class _EntryFieldEditDialog extends StatefulWidget {
  const _EntryFieldEditDialog({
    required this.entry,
    required this.controller,
    required this.kind,
  });

  final ScoutEntry entry;
  final ScoutingController controller;
  final _EntryFieldKind kind;

  @override
  State<_EntryFieldEditDialog> createState() => _EntryFieldEditDialogState();
}

class _EntryFieldEditDialogState extends State<_EntryFieldEditDialog> {
  late final TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(
      text: switch (widget.kind) {
        _EntryFieldKind.author => widget.entry.authorDisplayName,
        _EntryFieldKind.notes => widget.entry.notes,
      },
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    _EntryFieldKind.author => 'Scouted by',
    _EntryFieldKind.notes => 'Notes',
  };

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final updated = switch (widget.kind) {
      _EntryFieldKind.author => widget.entry.copyWith(
        authorDisplayName: _textCtrl.text,
      ),
      _EntryFieldKind.notes => widget.entry.copyWith(notes: _textCtrl.text),
    };
    setState(() => _saving = true);
    try {
      final saved = await widget.controller.saveEntry(updated);
      if (!mounted) return;
      if (!saved) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.controller.lastError ?? 'Save failed.'),
          ),
        );
        widget.controller.clearLastError();
        return;
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(width: 320, child: _buildInput()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildInput() => switch (widget.kind) {
    _EntryFieldKind.author => TextField(controller: _textCtrl),
    _EntryFieldKind.notes => TextField(controller: _textCtrl, maxLines: 4),
  };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasEntries, required this.syncState});

  final bool hasEntries;
  final ScoutingSyncState syncState;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String message) = switch (syncState) {
      ScoutingSyncState.signedOut => (
        Icons.lock_outline_rounded,
        'Sign in via the account icon\nto access the team database.',
      ),
      ScoutingSyncState.noAccess => (
        Icons.lock_outline_rounded,
        'Your account has no team access yet.\nAsk an admin to approve it.',
      ),
      ScoutingSyncState.syncing => (
        Icons.sync_rounded,
        'Loading entries from the database...',
      ),
      _ =>
        hasEntries
            ? (Icons.search_off_rounded, 'No entries match your filter.')
            : (
                Icons.inbox_rounded,
                'No scouting entries yet.\nEntries submitted by scouters will appear here.',
              ),
    };

    return EmptyState(icon: icon, message: message);
  }
}
