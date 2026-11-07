import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trex_trait.dart';
import '../models/trex_trait_report.dart';
import '../state/trex_trait_report_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';

class TrexDatabaseScreen extends StatefulWidget {
  const TrexDatabaseScreen({required this.controller, super.key});

  final TrexTraitReportController controller;

  @override
  State<TrexDatabaseScreen> createState() => _TrexDatabaseScreenState();
}

class _TrexDatabaseScreenState extends State<TrexDatabaseScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Set<String> _events = <String>{};
  Set<TrexTrait> _traits = <TrexTrait>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _events.isNotEmpty || _traits.isNotEmpty;

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_TrexDatabaseFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(
        allEvents: _eventNamesFrom(widget.controller.reports),
        selectedEvents: _events,
        selectedTraits: _traits,
      ),
    );
    if (result == null) return;
    setState(() {
      _events = result.events;
      _traits = result.traits;
    });
  }

  static List<String> _eventNamesFrom(List<TrexTraitReport> reports) {
    final names = <String>{
      for (final report in reports)
        if (report.eventName.trim().isNotEmpty) report.eventName.trim(),
    }.toList();
    names.sort();
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final reports = widget.controller.reports.where((report) {
          if (_events.isNotEmpty &&
              !_events.contains(report.eventName.trim())) {
            return false;
          }
          if (_traits.isEmpty) return true;
          final trait = TrexTrait.byKey(report.trait);
          return trait != null && _traits.contains(trait);
        }).toList();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            labelText: 'Search team number',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _openFilters,
                        tooltip: 'Filter by event or trait',
                        icon: Icon(
                          _hasActiveFilters
                              ? Icons.filter_alt_rounded
                              : Icons.filter_alt_outlined,
                          color: _hasActiveFilters
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _TrexReportList(
                    reports: reports,
                    search: _searchCtrl.text.trim(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrexDatabaseFilters {
  const _TrexDatabaseFilters({required this.events, required this.traits});

  final Set<String> events;
  final Set<TrexTrait> traits;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.allEvents,
    required this.selectedEvents,
    required this.selectedTraits,
  });

  final List<String> allEvents;
  final Set<String> selectedEvents;
  final Set<TrexTrait> selectedTraits;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _events = {...widget.selectedEvents};
  late Set<TrexTrait> _traits = {...widget.selectedTraits};

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text('Filter', style: textTheme.titleMedium)),
                TextButton(
                  onPressed: () => setState(() {
                    _events = <String>{};
                    _traits = <TrexTrait>{};
                  }),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Events', style: textTheme.labelLarge),
                ),
                if (widget.allEvents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'No reports carry an event name yet.',
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final event in widget.allEvents)
                    CheckboxListTile(
                      dense: true,
                      value: _events.contains(event),
                      title: Text(event),
                      onChanged: (_) => setState(() {
                        if (!_events.remove(event)) _events.add(event);
                      }),
                    ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Traits', style: textTheme.labelLarge),
                ),
                for (final trait in TrexTrait.values)
                  CheckboxListTile(
                    dense: true,
                    value: _traits.contains(trait),
                    title: Text(trait.label),
                    onChanged: (_) => setState(() {
                      if (!_traits.remove(trait)) _traits.add(trait);
                    }),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: StrategyPalette.borderOf(context)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop(_TrexDatabaseFilters(events: _events, traits: _traits)),
              child: const Text('Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrexReportList extends StatelessWidget {
  const _TrexReportList({required this.reports, required this.search});

  final List<TrexTraitReport> reports;
  final String search;

  @override
  Widget build(BuildContext context) {
    final byTeam = <int, List<TrexTraitReport>>{};
    for (final report in reports) {
      (byTeam[report.teamNumber] ??= <TrexTraitReport>[]).add(report);
    }
    var teams = byTeam.keys.toList()..sort();
    if (search.isNotEmpty) {
      teams = teams.where((t) => t.toString().contains(search)).toList();
    }
    if (teams.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        message: reports.isEmpty
            ? 'No T-Rex reports match the current filters.'
            : 'No team matches "$search".',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final team in teams)
          _TeamGroup(team: team, reports: byTeam[team]!),
      ],
    );
  }
}

class _TeamGroup extends StatelessWidget {
  const _TeamGroup({required this.team, required this.reports});

  final int team;
  final List<TrexTraitReport> reports;

  @override
  Widget build(BuildContext context) {
    final byTrait = <TrexTrait, List<TrexTraitReport>>{};
    for (final report in reports) {
      final trait = TrexTrait.byKey(report.trait);
      if (trait == null) continue;
      (byTrait[trait] ??= <TrexTraitReport>[]).add(report);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Team $team',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${reports.length} '
            '${reports.length == 1 ? 'report' : 'reports'}',
          ),
          children: [
            for (final trait in TrexTrait.values)
              if (byTrait[trait] case final entries? when entries.isNotEmpty)
                _TraitGroup(trait: trait, reports: entries),
          ],
        ),
      ),
    );
  }
}

class _TraitGroup extends StatelessWidget {
  const _TraitGroup({required this.trait, required this.reports});

  final TrexTrait trait;
  final List<TrexTraitReport> reports;

  @override
  Widget build(BuildContext context) {
    final sorted = reports.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trait.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final report in sorted) _ReportCard(report: report),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final TrexTraitReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Match ${report.matchNumber}'
            '${report.eventName.isEmpty ? '' : ' · ${report.eventName}'}',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (report.report.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(report.report, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          Text(
            report.authorDisplayName.isEmpty
                ? 'Unknown scouter'
                : report.authorDisplayName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
