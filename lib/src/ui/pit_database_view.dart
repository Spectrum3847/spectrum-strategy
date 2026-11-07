import 'package:flutter/material.dart';

import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../widgets/empty_state.dart';
import 'pit_entry_card.dart';

class PitDatabaseView extends StatefulWidget {
  const PitDatabaseView({
    required this.controller,
    required this.configController,
    this.teamFilter,
    super.key,
  });

  final PitScoutingController controller;
  final PitScoutConfigController configController;

  final int? teamFilter;

  @override
  State<PitDatabaseView> createState() => _PitDatabaseViewState();
}

class _PitDatabaseViewState extends State<PitDatabaseView> {
  int? _selectedTeam;

  @override
  void didUpdateWidget(PitDatabaseView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.teamFilter != oldWidget.teamFilter) {
      _selectedTeam = widget.teamFilter;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.configController,
      ]),
      builder: (context, _) {
        final all = widget.controller.entries;
        final filtered = widget.teamFilter == null
            ? all
            : all
                  .where((e) => e.teamNumber == widget.teamFilter)
                  .toList(growable: false);

        final sorted = [...filtered]
          ..sort((a, b) {
            final byUpdated = a.updatedAt.compareTo(b.updatedAt);
            if (byUpdated != 0) return byUpdated;
            return a.teamNumber.compareTo(b.teamNumber);
          });

        if (sorted.isEmpty) {
          return EmptyState(
            icon: Icons.build_outlined,
            message: all.isEmpty
                ? 'No pit entries submitted yet.'
                : 'No pit entries match that team filter.',
          );
        }

        final teams = <int>{
          for (final entry in sorted) entry.teamNumber,
        }.toList()..sort();

        var selected = widget.teamFilter ?? _selectedTeam;
        if (selected != null && !teams.contains(selected)) selected = null;
        final visible = selected == null
            ? sorted
            : sorted
                  .where((e) => e.teamNumber == selected)
                  .toList(growable: false);

        final teamOpen = selected != null;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                if (widget.teamFilter == null && teams.length > 1)
                  _TeamTabs(
                    teams: teams,
                    selected: selected,
                    onSelect: (team) => setState(() => _selectedTeam = team),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return PitEntryCard(
                        key: ValueKey(
                          '${entry.id}:${teamOpen ? 'open' : 'shut'}',
                        ),
                        entry: entry,
                        controller: widget.controller,
                        config: widget.configController.config,
                        initiallyExpanded: teamOpen,
                      );
                    },
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

class _TeamTabs extends StatelessWidget {
  const _TeamTabs({
    required this.teams,
    required this.selected,
    required this.onSelect,
  });

  final List<int> teams;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          for (final team in teams)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$team'),
                selected: selected == team,
                onSelected: (_) => onSelect(team),
              ),
            ),
        ],
      ),
    );
  }
}
