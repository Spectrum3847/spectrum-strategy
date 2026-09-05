import 'package:flutter/material.dart';
import 'package:tba_client/tba_client.dart';

import '../state/event_sections_controller.dart';
import '../theme/strategy_palette.dart';

class EventSectionsView extends StatelessWidget {
  const EventSectionsView({
    required this.controller,
    required this.onSelectionChanged,
    super.key,
  });

  final EventSectionsController controller;

  final VoidCallback onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionsHeader(
              controller: controller,
              onPick: () => _pick(context),
            ),
            if (controller.isAllHidden)
              const _SectionNotice(
                text:
                    'The schedule and stats are always shown. Tap Sections to '
                    'add rankings, alliances or awards.',
              )
            else ...[
              if (controller.error != null)
                _SectionNotice(text: controller.error!),
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (controller.isVisible(EventSection.rankings))
                  _RankingsSection(rankings: controller.rankings),
                if (controller.isVisible(EventSection.alliances))
                  _AlliancesSection(alliances: controller.alliances),
                if (controller.isVisible(EventSection.awards))
                  _AwardsSection(awards: controller.awards),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<void> _pick(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SectionPickerSheet(
        controller: controller,
        onChanged: onSelectionChanged,
      ),
    );
  }
}

class _SectionsHeader extends StatelessWidget {
  const _SectionsHeader({required this.controller, required this.onPick});

  final EventSectionsController controller;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final count = controller.visible.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Event page',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(count == 0 ? 'Sections' : 'Sections ($count)'),
          ),
        ],
      ),
    );
  }
}

class _SectionPickerSheet extends StatelessWidget {
  const _SectionPickerSheet({
    required this.controller,
    required this.onChanged,
  });

  final EventSectionsController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Event page sections',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await controller.showAll();
                        onChanged();
                      },
                      child: const Text('All'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await controller.hideAll();
                        onChanged();
                      },
                      child: const Text('None'),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final section in EventSection.values)
                      SwitchListTile(
                        title: Text(section.label),
                        subtitle: Text(section.description),
                        value: controller.isVisible(section),
                        onChanged: (_) async {
                          await controller.toggle(section);
                          onChanged();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _SectionNotice extends StatelessWidget {
  const _SectionNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _RankingsSection extends StatelessWidget {
  const _RankingsSection({required this.rankings});

  final TbaEventRankings? rankings;

  @override
  Widget build(BuildContext context) {
    final rows = rankings?.rankings ?? const <TbaTeamRanking>[];
    if (rows.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading('Rankings'),
          _SectionNotice(
            text: 'No rankings yet. They appear once quals start.',
          ),
        ],
      );
    }

    final sortName = rankings?.sortOrderNames.firstOrNull;

    final rpName = rankings?.extraStatsNames.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading('Rankings'),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            columns: <DataColumn>[
              const DataColumn(label: Text('#')),
              const DataColumn(label: Text('Team')),
              if (sortName != null) DataColumn(label: Text(sortName)),
              if (rpName != null) DataColumn(label: Text(rpName)),
              const DataColumn(label: Text('Record')),
              const DataColumn(label: Text('Played')),
            ],
            rows: <DataRow>[
              for (final row in rows)
                DataRow(
                  cells: <DataCell>[
                    DataCell(Text('${row.rank}')),
                    DataCell(Text(_teamNumber(row.teamKey))),
                    if (sortName != null)
                      DataCell(
                        Text(
                          row.sortOrders.isEmpty
                              ? '-'
                              : _trim(row.sortOrders.first),
                        ),
                      ),
                    if (rpName != null)
                      DataCell(
                        Text(
                          row.extraStats.isEmpty
                              ? '-'
                              : _trim(row.extraStats.first),
                        ),
                      ),
                    DataCell(Text(row.record)),
                    DataCell(Text('${row.matchesPlayed}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlliancesSection extends StatelessWidget {
  const _AlliancesSection({required this.alliances});

  final TbaEventAlliances? alliances;

  @override
  Widget build(BuildContext context) {
    final rows = alliances?.alliances ?? const <TbaAlliance>[];
    if (rows.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading('Alliances'),
          _SectionNotice(
            text: 'No alliances yet. They appear after alliance selection.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading('Alliances'),
        for (final alliance in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    alliance.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    alliance.picks.map(_teamNumber).join(', '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (alliance.record.isNotEmpty)
                  Text(
                    alliance.record,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _AwardsSection extends StatelessWidget {
  const _AwardsSection({required this.awards});

  final TbaEventAwards? awards;

  @override
  Widget build(BuildContext context) {
    final rows = awards?.awards ?? const <TbaAward>[];
    if (rows.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading('Awards'),
          _SectionNotice(
            text: 'No awards yet. They appear after the awards ceremony.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading('Awards'),
        for (final award in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(award.name, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  _recipients(award),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Divider(height: 12, color: StrategyPalette.borderOf(context)),
              ],
            ),
          ),
      ],
    );
  }

  static String _recipients(TbaAward award) {
    final parts = <String>[
      for (final recipient in award.recipients)
        if (recipient.awardee != null)
          recipient.teamKey == null
              ? recipient.awardee!
              : '${recipient.awardee!} (${_teamNumber(recipient.teamKey!)})'
        else if (recipient.teamKey != null)
          _teamNumber(recipient.teamKey!),
    ];
    return parts.isEmpty ? 'Not awarded' : parts.join(', ');
  }
}

String _teamNumber(String teamKey) =>
    teamKey.startsWith('frc') ? teamKey.substring(3) : teamKey;

String _trim(num value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}
