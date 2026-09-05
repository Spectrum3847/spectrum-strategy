import 'package:flutter/material.dart';

import '../models/event_stat_table.dart';
import '../state/event_stats_controller.dart';
import '../theme/strategy_palette.dart';

class EventStatTableView extends StatefulWidget {
  const EventStatTableView({required this.controller, super.key});

  final EventStatsController controller;

  @override
  State<EventStatTableView> createState() => _EventStatTableViewState();
}

class _EventStatTableViewState extends State<EventStatTableView> {
  String? _sortStat;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final columns = controller.visibleColumns;

        final sortStat = columns.contains(_sortStat) ? _sortStat : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatTableHeader(
              controller: controller,
              onPickColumns: () => _pickColumns(context),
            ),
            if (controller.isLoading && controller.table.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.error != null)
              _StatNotice(text: controller.error!)
            else if (controller.hasNoStats)
              const _StatNotice(
                text:
                    'TBA has no stats for this event yet. They appear once '
                    'enough matches have been played.',
              )
            else if (columns.isEmpty)
              _StatNotice(
                text: controller.selectedColumns.isEmpty
                    ? 'No columns chosen. Tap Columns to pick some.'
                    : 'This event reports none of your chosen columns. Tap '
                          'Columns to pick from what it does report.',
              )
            else
              _StatGrid(
                table: controller.table,
                columns: columns,
                sortStat: sortStat,
                onSort: (stat) =>
                    setState(() => _sortStat = _sortStat == stat ? null : stat),
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickColumns(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ColumnPickerSheet(controller: widget.controller),
    );
  }
}

class _StatTableHeader extends StatelessWidget {
  const _StatTableHeader({
    required this.controller,
    required this.onPickColumns,
  });

  final EventStatsController controller;
  final VoidCallback onPickColumns;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Event stats', style: textTheme.titleSmall),
                Text(
                  'From The Blue Alliance. Tap a column to sort.',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onPickColumns,
            icon: const Icon(Icons.view_column_outlined, size: 18),
            label: const Text('Columns'),
          ),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.table,
    required this.columns,
    required this.sortStat,
    required this.onSort,
  });

  final EventStatTable table;
  final List<String> columns;
  final String? sortStat;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final teams = _sortedTeams();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columnSpacing: 24,
        sortColumnIndex: sortStat == null
            ? null
            : columns.indexOf(sortStat!) + 1,

        sortAscending: false,
        columns: <DataColumn>[
          const DataColumn(label: Text('Team')),
          for (final stat in columns)
            DataColumn(
              label: Text(stat),
              numeric: true,
              onSort: (_, _) => onSort(stat),
            ),
        ],
        rows: <DataRow>[
          for (final team in teams)
            DataRow(
              cells: <DataCell>[
                DataCell(Text('$team')),
                for (final stat in columns)
                  DataCell(Text(_format(table.valueFor(team, stat)))),
              ],
            ),
        ],
      ),
    );
  }

  List<int> _sortedTeams() {
    final teams = table.teams.toList();
    final stat = sortStat;
    if (stat == null) return teams;
    teams.sort((a, b) {
      final va = table.valueFor(a, stat);
      final vb = table.valueFor(b, stat);

      if (va == null && vb == null) return a.compareTo(b);
      if (va == null) return 1;
      if (vb == null) return -1;
      return vb.compareTo(va);
    });
    return teams;
  }

  static String _format(num? value) =>
      value == null ? '' : value.toStringAsFixed(2);
}

class _StatNotice extends StatelessWidget {
  const _StatNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ColumnPickerSheet extends StatelessWidget {
  const _ColumnPickerSheet({required this.controller});

  final EventStatsController controller;

  List<String> get _statsToOffer {
    final fromEvent = controller.table.statNames;
    if (fromEvent.isNotEmpty) return fromEvent;
    return <String>{
      ...defaultStatColumns,
      ...controller.selectedColumns,
    }.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.selectedColumns;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Columns',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: controller.resetColumns,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (controller.table.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'TBA has no stats for this event yet, so this is the '
                          'curated default. The rest of the columns appear once '
                          'enough matches have been played.',

                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),

                    for (final stat in _statsToOffer)
                      CheckboxListTile(
                        dense: true,
                        value: selected.contains(stat),
                        title: Text(stat),
                        onChanged: (_) => controller.toggleColumn(stat),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: StrategyPalette.borderOf(context)),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
