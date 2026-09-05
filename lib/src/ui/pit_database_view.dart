import 'package:flutter/material.dart';

import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../widgets/empty_state.dart';
import 'pit_entry_card.dart';

class PitDatabaseView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final all = controller.entries;
    final filtered = teamFilter == null
        ? all
        : all.where((e) => e.teamNumber == teamFilter).toList(growable: false);

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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final entry = sorted[index];
            return PitEntryCard(
              key: ValueKey(entry.id),
              entry: entry,
              controller: controller,
              config: configController.config,
            );
          },
        ),
      ),
    );
  }
}
