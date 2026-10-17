import 'package:flutter/material.dart';

import '../../models/draft_board.dart';
import '../../models/pick_layout.dart';
import '../../models/pick_list.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/glass_modal.dart';
import 'pick_facts.dart';

class DraftBoardView extends StatelessWidget {
  const DraftBoardView({
    required this.board,
    required this.facts,
    required this.layout,
    required this.ourTeam,
    required this.canUndo,
    required this.onOpenTeam,
    required this.onAccept,
    required this.onDecline,
    required this.onUndo,
    required this.onReset,
    super.key,
  });

  final DraftBoard board;
  final PickFacts facts;

  final PickLayout? layout;
  final int? ourTeam;
  final bool canUndo;
  final ValueChanged<int> onOpenTeam;
  final ValueChanged<int> onAccept;
  final ValueChanged<int> onDecline;
  final VoidCallback onUndo;
  final VoidCallback onReset;

  static const int _listed = 24;

  List<_Candidate> _candidates() {
    final out = <_Candidate>[];
    final seen = <int>{};
    final dnp = {for (final d in layout?.dnp ?? const <DoNotPick>[]) d.team: d};
    void add(int team, String label) {
      if (out.length >= _listed || !board.canInvite(team) || !seen.add(team)) {
        return;
      }
      out.add(_Candidate(team, label, dnp[team]?.reason));
    }

    final current = layout;
    if (current != null) {
      for (final tier in current.tiers) {
        for (final team in tier.teams) {
          add(team, tier.name);
        }
      }
    }
    for (final team in facts.ranking) {
      add(team, 'Not on the list');
    }
    return out;
  }

  Future<void> _record(BuildContext context, _Candidate candidate) {
    final picking = board.picking;
    if (picking == null) return Future<void>.value();
    return showGlassModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final text = Theme.of(sheet).textTheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Alliance ${picking + 1} invites ${candidate.team}',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(facts.stat(candidate.team), style: text.bodyMedium),
                if (candidate.dnpReason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'On your do-not-pick list: ${candidate.dnpReason}',
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(sheet).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        onAccept(candidate.team);
                      },
                      child: const Text('Accepted'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        onDecline(candidate.team);
                      },
                      child: const Text('Declined'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheet).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showGlassConfirmDialog<bool>(
      context: context,
      title: 'Reset the draft?',
      content: const Text('Clears every pick and decline on this board.'),
      actionsBuilder: (dialog) => [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('Reset'),
        ),
      ],
    );
    if (ok == true) onReset();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final border = StrategyPalette.borderOf(context);
    final candidates = _candidates();
    final picking = board.picking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          picking == null
              ? 'Draft complete'
              : 'Round ${board.round + 1} of ${DraftBoard.rounds}',
          style: text.bodySmall?.copyWith(color: muted),
        ),
        Text(
          picking == null
              ? 'Every alliance is full.'
              : 'Alliance ${picking + 1} is on the clock',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Undo'),
            ),
            TextButton(
              onPressed: canUndo ? () => _confirmReset(context) : null,
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < board.alliances.length; i++)
          _AllianceRow(
            key: ValueKey('alliance-${i + 1}'),
            number: i + 1,
            alliance: board.alliances[i],
            onTheClock: i == picking,
            ourTeam: ourTeam,
            onOpenTeam: onOpenTeam,
          ),
        const SizedBox(height: 16),
        Divider(height: 1, color: border),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Semantics(
            header: true,
            child: Text(
              'Best available',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Text(
          'Your pick list first, then seeding. Tap a team to record it.',
          style: text.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 4),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No eligible teams left.', style: text.bodyMedium),
          ),
        for (final candidate in candidates)
          _CandidateRow(
            key: ValueKey('free-${candidate.team}'),
            candidate: candidate,
            stat: facts.stat(candidate.team),
            onTheClock: picking != null,
            onOpenTeam: () => onOpenTeam(candidate.team),
            onRecord: () => _record(context, candidate),
          ),
      ],
    );
  }
}

class _Candidate {
  const _Candidate(this.team, this.label, this.dnpReason);
  final int team;
  final String label;
  final String? dnpReason;
}

class _AllianceRow extends StatelessWidget {
  const _AllianceRow({
    required this.number,
    required this.alliance,
    required this.onTheClock,
    required this.ourTeam,
    required this.onOpenTeam,
    super.key,
  });

  final int number;
  final DraftAlliance alliance;
  final bool onTheClock;
  final int? ourTeam;
  final ValueChanged<int> onOpenTeam;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final teams = alliance.teams;
    final open = 4 - teams.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: onTheClock ? StrategyPalette.surfaceStrongOf(context) : null,
        border: Border.all(
          color: onTheClock
              ? Theme.of(context).colorScheme.primary
              : StrategyPalette.borderOf(context),
        ),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Semantics(
        label:
            'Alliance $number: ${teams.join(', ')}'
            '${onTheClock ? ', on the clock' : ''}',
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$number',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < teams.length; i++)
                    TextButton(
                      onPressed: () => onOpenTeam(teams[i]),
                      child: Text(
                        '${teams[i]}${teams[i] == ourTeam ? ' (us)' : ''}',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: i == 0 ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  if (open > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$open open',
                        style: text.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                ],
              ),
            ),
            if (onTheClock)
              Text(
                'On the clock',
                style: text.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.stat,
    required this.onTheClock,
    required this.onOpenTeam,
    required this.onRecord,
    super.key,
  });

  final _Candidate candidate;
  final String stat;
  final bool onTheClock;
  final VoidCallback onOpenTeam;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final error = Theme.of(context).colorScheme.error;
    final dnp = candidate.dnpReason;
    return InkWell(
      onTap: onTheClock ? onRecord : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            TextButton(
              onPressed: onOpenTeam,
              child: Text(
                '${candidate.team}',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stat, style: text.bodySmall),
                    Text(
                      dnp == null ? candidate.label : 'Do not pick: $dnp',
                      style: text.bodySmall?.copyWith(
                        color: dnp == null ? muted : error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onTheClock) Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }
}
