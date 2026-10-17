import 'package:flutter/material.dart';

import '../../models/pick_layout.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/glass_popup_menu.dart';
import 'pick_facts.dart';
import 'prompt_dialog.dart';

class PickListView extends StatelessWidget {
  const PickListView({
    required this.layout,
    required this.facts,
    required this.picked,
    required this.onOpenTeam,
    required this.onChanged,
    super.key,
  });

  final PickLayout layout;
  final PickFacts facts;
  final Map<int, String> picked;
  final ValueChanged<int> onOpenTeam;
  final ValueChanged<PickLayout> onChanged;

  Future<void> _addTeam(BuildContext context, int tier) async {
    final text = await showPrompt(
      context,
      title: 'Add to ${layout.tiers[tier].name}',
      label: 'Team number',
      confirmLabel: 'Add',
      digitsOnly: true,
      validate: _teamError,
    );
    if (text != null) onChanged(layout.add(int.parse(text), tier: tier));
  }

  String? _teamError(String text) {
    final team = int.tryParse(text);
    if (team == null || team < 1 || team > 99999) {
      return 'Enter a team number, like 3847.';
    }
    final known = facts.knownTeams;
    if (known.isNotEmpty && !known.contains(team)) {
      return 'Team $team is not at this event.';
    }
    return null;
  }

  static String? _reasonError(String text) =>
      text.isEmpty ? 'Say why, so the drive team trusts it.' : null;

  Future<void> _markDnp(BuildContext context, int team) async {
    final reason = await showPrompt(
      context,
      title: 'Do not pick $team',
      label: 'Reason',
      confirmLabel: 'Do not pick',
      validate: _reasonError,
    );
    if (reason != null) onChanged(layout.markDnp(team, reason));
  }

  Future<void> _addDnp(BuildContext context) async {
    final text = await showPrompt(
      context,
      title: 'Do not pick',
      label: 'Team number',
      confirmLabel: 'Next',
      digitsOnly: true,
      validate: _teamError,
    );
    if (text == null || !context.mounted) return;
    await _markDnp(context, int.parse(text));
  }

  Future<void> _editReason(BuildContext context, int team, String old) async {
    final reason = await showPrompt(
      context,
      title: 'Reason for $team',
      label: 'Reason',
      confirmLabel: 'Save',
      initial: old,
      validate: _reasonError,
    );
    if (reason != null) onChanged(layout.setReason(team, reason));
  }

  Future<void> _renameTier(BuildContext context, int tier) async {
    final name = await showPrompt(
      context,
      title: 'Rename tier',
      label: 'Tier name',
      confirmLabel: 'Save',
      initial: layout.tiers[tier].name,
      validate: (t) => t.isEmpty ? 'Give the tier a name.' : null,
    );
    if (name != null) onChanged(layout.renameTier(tier, name));
  }

  Future<void> _addTier(BuildContext context) async {
    final name = await showPrompt(
      context,
      title: 'New tier',
      label: 'Tier name',
      confirmLabel: 'Add',
      validate: (t) => t.isEmpty ? 'Give the tier a name.' : null,
    );
    if (name != null) onChanged(layout.addTier(name.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final rows = layout.rows;
    final total = rows.whereType<TeamRow>().length;
    final surface = StrategyPalette.surfaceStrongOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: rows.length,
          onReorderItem: (from, to) => onChanged(layout.reorder(from, to)),
          proxyDecorator: (child, _, _) =>
              Material(color: surface, child: child),
          itemBuilder: (context, i) => switch (rows[i]) {
            TierRow(:final tier) => _TierHeader(
              key: ValueKey('tier-$tier'),
              name: layout.tiers[tier].name,
              count: layout.tiers[tier].teams.length,
              canRemove:
                  layout.tiers.length > 1 && layout.tiers[tier].teams.isEmpty,
              onAdd: () => _addTeam(context, tier),
              onRename: () => _renameTier(context, tier),
              onRemove: () => onChanged(layout.removeTier(tier)),
            ),
            TeamRow(:final team, :final tier, :final rank) => _TeamTile(
              key: ValueKey('team-$team'),
              index: i,
              team: team,
              rank: rank,
              stat: facts.stat(team),
              flags: facts.flags(team),
              taken: picked[team],
              isFirst: tier == 0 && rank == 1,
              isLast: tier == layout.tiers.length - 1 && rank == total,
              tierNames: [for (final t in layout.tiers) t.name],
              currentTier: tier,
              onOpenTeam: () => onOpenTeam(team),
              onMove: (delta) => onChanged(layout.move(team, delta)),
              onMoveToTier: (t) => onChanged(layout.moveToTier(team, t)),
              onDnp: () => _markDnp(context, team),
              onRemove: () => onChanged(layout.remove(team)),
            ),
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addTier(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add tier'),
          ),
        ),
        const SizedBox(height: 8),
        _DnpSection(
          layout: layout,
          facts: facts,
          onAdd: () => _addDnp(context),
          onOpenTeam: onOpenTeam,
          onEditReason: (team, old) => _editReason(context, team, old),
          onMoveToTier: (team, t) => onChanged(layout.moveToTier(team, t)),
          onRemove: (team) => onChanged(layout.remove(team)),
        ),
      ],
    );
  }
}

class _TierHeader extends StatelessWidget {
  const _TierHeader({
    required this.name,
    required this.count,
    required this.canRemove,
    required this.onAdd,
    required this.onRename,
    required this.onRemove,
    super.key,
  });

  final String name;
  final int count;
  final bool canRemove;
  final VoidCallback onAdd;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: StrategyPalette.borderOf(context)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    '$name ($count)',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add team to $name',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
              ),
              GlassPopupMenuButton<String>(
                tooltip: 'Tier options for $name',
                onSelected: (value) =>
                    value == 'rename' ? onRename() : onRemove(),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename tier'),
                  ),
                  if (canRemove)
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove tier'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (count == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No teams. Add one, or move a team here.',
              style: text.bodySmall?.copyWith(
                color: StrategyPalette.mutedTextOf(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.index,
    required this.team,
    required this.rank,
    required this.stat,
    required this.flags,
    required this.taken,
    required this.isFirst,
    required this.isLast,
    required this.tierNames,
    required this.currentTier,
    required this.onOpenTeam,
    required this.onMove,
    required this.onMoveToTier,
    required this.onDnp,
    required this.onRemove,
    super.key,
  });

  final int index;
  final int team;
  final int rank;
  final String stat;
  final String? flags;
  final String? taken;
  final bool isFirst;
  final bool isLast;
  final List<String> tierNames;
  final int currentTier;
  final VoidCallback onOpenTeam;
  final ValueChanged<int> onMove;
  final ValueChanged<int> onMoveToTier;
  final VoidCallback onDnp;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final ink = taken != null ? muted : null;
    final detail = <String>[?taken, stat, ?flags];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.drag_indicator_rounded),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: text.bodyMedium?.copyWith(color: muted),
              ),
            ),
            TextButton(
              onPressed: onOpenTeam,
              style: TextButton.styleFrom(foregroundColor: ink),
              child: Text(
                '$team',
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Move $team up',
              onPressed: isFirst ? null : () => onMove(-1),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Move $team down',
              onPressed: isLast ? null : () => onMove(1),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            GlassPopupMenuButton<String>(
              tooltip: 'More for $team',
              onSelected: (value) {
                if (value == 'dnp') return onDnp();
                if (value == 'remove') return onRemove();
                onMoveToTier(int.parse(value));
              },
              itemBuilder: (_) => [
                for (var i = 0; i < tierNames.length; i++)
                  if (i != currentTier)
                    PopupMenuItem(
                      value: '$i',
                      child: Text('Move to ${tierNames[i]}'),
                    ),
                const PopupMenuItem(value: 'dnp', child: Text('Do not pick')),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
          child: Text(
            detail.join('\n'),
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

class _DnpSection extends StatelessWidget {
  const _DnpSection({
    required this.layout,
    required this.facts,
    required this.onAdd,
    required this.onOpenTeam,
    required this.onEditReason,
    required this.onMoveToTier,
    required this.onRemove,
  });

  final PickLayout layout;
  final PickFacts facts;
  final VoidCallback onAdd;
  final ValueChanged<int> onOpenTeam;
  final void Function(int team, String reason) onEditReason;
  final void Function(int team, int tier) onMoveToTier;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: StrategyPalette.borderOf(context)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Do not pick (${layout.dnp.length})',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add a do-not-pick team',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        if (layout.dnp.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No teams. Every one needs a reason.',
              style: text.bodySmall?.copyWith(color: muted),
            ),
          ),
        for (final entry in layout.dnp)
          Row(
            key: ValueKey('dnp-${entry.team}'),
            children: [
              TextButton(
                onPressed: () => onOpenTeam(entry.team),
                child: Text(
                  '${entry.team}',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.reason, style: text.bodyMedium),
                    Text(
                      facts.stat(entry.team),
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit reason for ${entry.team}',
                onPressed: () => onEditReason(entry.team, entry.reason),
                icon: const Icon(Icons.edit_outlined),
              ),
              GlassPopupMenuButton<String>(
                tooltip: 'More for ${entry.team}',
                onSelected: (value) => value == 'remove'
                    ? onRemove(entry.team)
                    : onMoveToTier(entry.team, int.parse(value)),
                itemBuilder: (_) => [
                  for (var i = 0; i < layout.tiers.length; i++)
                    PopupMenuItem(
                      value: '$i',
                      child: Text('Move to ${layout.tiers[i].name}'),
                    ),
                  const PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
      ],
    );
  }
}
