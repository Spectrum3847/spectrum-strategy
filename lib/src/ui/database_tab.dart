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
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../services/scout_export_service.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/entry_flag_badge.dart';
import 'glass_chrome.dart';
import '../widgets/glass_popup_menu.dart';

class DatabaseTab extends StatefulWidget {
  const DatabaseTab({
    required this.scoutingController,
    required this.configController,
    required this.canEditAnyEntry,
    required this.eventController,
    this.currentUserUid,
    super.key,
  });

  final ScoutingController scoutingController;

  final EventController eventController;

  final ScoutConfigController configController;

  final bool canEditAnyEntry;

  final String? currentUserUid;

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

class _DatabaseTabState extends State<DatabaseTab> {
  final TextEditingController _teamFilter = TextEditingController();
  final TextEditingController _matchFilter = TextEditingController();
  bool _isRefreshing = false;
  bool _isExporting = false;
  EntryOrder _order = EntryOrder.spreadsheet;
  final Map<String, double> _columnWidths = {};
  final ScoutExportService _exportService = ScoutExportService();

  static const String _orderPrefsKey = 'database_entry_order';

  int _memoRevision = -1;
  String _memoTeamText = '';
  String _memoMatchText = '';
  EntryOrder _memoOrder = EntryOrder.spreadsheet;
  bool _memoWantsFlags = false;
  List<StatboticsMatch>? _memoScheduleSource;
  List<ScoutEntry> _memoFiltered = const <ScoutEntry>[];
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

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await widget.scoutingController.syncNow();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _exportCsv() async {
    final eventKey = widget.eventController.eventKey;
    if (eventKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load an event before exporting.')),
      );
      return;
    }
    setState(() => _isExporting = true);
    try {
      final result = await _exportService.shareCsv(
        config: widget.configController.config,
        entries: widget.scoutingController.entries,
        eventKey: eventKey,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.savedMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  double _colWidth(String key, {double d = 100}) =>
      _columnWidths.putIfAbsent(key, () => d);

  bool _canEditEntry(ScoutEntry entry) =>
      widget.canEditAnyEntry ||
      (widget.currentUserUid != null &&
          widget.currentUserUid!.isNotEmpty &&
          entry.authorUid == widget.currentUserUid);

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
    return Padding(
      padding: EdgeInsets.only(bottom: GlassChrome.bottomInsetOf(context)),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.scoutingController,
          widget.configController,
          widget.eventController,
        ]),
        builder: (context, _) {
          final all = widget.scoutingController.entries;
          final syncStatus = widget.scoutingController.syncStatus;

          _refreshDerived(all, true);
          final filtered = _memoFiltered;
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
                  onExport: widget.canEditAnyEntry ? _exportCsv : null,
                  isExporting: _isExporting,
                  onFilterChanged: () => setState(() {}),
                ),
                Expanded(child: _buildTableView(filtered, flags)),
              ],
            ),
          );
        },
      ),
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
    this.onExport,
    this.isExporting = false,
    required this.onFilterChanged,
  });

  final EntryOrder order;
  final ValueChanged<EntryOrder> onOrderChanged;

  final TextEditingController teamFilter;
  final TextEditingController matchFilter;
  final ScoutingSyncStatus syncStatus;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  final VoidCallback? onExport;
  final bool isExporting;
  final VoidCallback onFilterChanged;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _orderControl(context),
                    if (onExport != null)
                      OutlinedButton.icon(
                        onPressed: isExporting ? null : onExport,
                        icon: isExporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.file_download_outlined,
                                size: 18,
                              ),
                        label: const Text('Export CSV'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildFilterRow(context),
                const SizedBox(height: 6),
                _SyncStatusRow(status: syncStatus),
              ],
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

  Widget _orderControl(BuildContext context) {
    return GlassPopupMenuButton<EntryOrder>(
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
              const SizedBox(height: 8),
              matchField,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: teamField),
            const SizedBox(width: 8),
            Expanded(child: matchField),
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
  final intValue = storedCounterValue(value) ?? 0;
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
        fType == ScoutFieldType.longText ||
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
      case ScoutFieldType.longText:
        return TextField(controller: _textCtrl, minLines: 3, maxLines: 6);
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
        final intValue = storedCounterValue(_value) ?? 0;
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
      case ScoutFieldType.document:
        return Text(
          'Attachments are edited from the pit scouting form.',
          style: Theme.of(context).textTheme.bodySmall,
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
