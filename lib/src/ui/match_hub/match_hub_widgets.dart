import 'package:flutter/material.dart';

import '../../services/match_brief_sync_service.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/sync_status_pill.dart';

class HubSection extends StatelessWidget {
  const HubSection({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class HubTeamLink extends StatelessWidget {
  const HubTeamLink({
    required this.team,
    required this.nickname,
    this.onTap,
    this.style,
    super.key,
  });

  final int team;
  final String nickname;
  final VoidCallback? onTap;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final muted = StrategyPalette.mutedTextOf(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$team',
                  style: style?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (nickname.isNotEmpty)
                  TextSpan(
                    text: '  $nickname',
                    style: style?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MatchBriefSyncChip extends StatelessWidget {
  const MatchBriefSyncChip({required this.status, super.key});

  final MatchBriefSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon) = switch (status.state) {
      MatchBriefSyncState.signedOut => (
        'Not signed in to sync',
        Icons.cloud_off_rounded,
      ),
      MatchBriefSyncState.noAccess => (
        'No team access yet',
        Icons.lock_outline_rounded,
      ),
      MatchBriefSyncState.syncing => ('Syncing...', Icons.sync_rounded),
      MatchBriefSyncState.synced => ('Synced', Icons.cloud_done_rounded),
      MatchBriefSyncState.offline => ('Offline', Icons.cloud_off_rounded),
      MatchBriefSyncState.rejected => (
        'Not accepted',
        Icons.report_gmailerrorred_rounded,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: SyncStatusPill(
        label: label,
        icon: icon,
        isFailure: status.state == MatchBriefSyncState.rejected,
        tooltip: status.error,
      ),
    );
  }
}
