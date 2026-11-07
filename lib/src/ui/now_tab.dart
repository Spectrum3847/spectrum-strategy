import 'dart:async';

import 'package:flutter/material.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../models/now_summary.dart';
import '../scouting/services/scouting_sync_service.dart';
import '../scouting/state/scout_shift_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/event_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import 'glass_chrome.dart';

class NowTab extends StatefulWidget {
  const NowTab({
    required this.eventController,
    required this.scoutingController,
    required this.onOpenTeam,
    required this.onPrepMatch,
    required this.onOpenScout,
    required this.onOpenSettings,
    this.onOpenDatabase,
    this.shiftController,
    this.currentUid,
    this.isLead = false,
    super.key,
  });

  final EventController eventController;
  final ScoutingController scoutingController;

  final ScoutShiftController? shiftController;

  final String? currentUid;

  final bool isLead;

  final ValueChanged<int> onOpenTeam;
  final ValueChanged<StatboticsMatch> onPrepMatch;
  final VoidCallback onOpenScout;
  final VoidCallback onOpenSettings;

  final VoidCallback? onOpenDatabase;

  @override
  State<NowTab> createState() => _NowTabState();
}

class _NowTabState extends State<NowTab> {
  String _watchedEventKey = '';

  @override
  void initState() {
    super.initState();
    widget.eventController.addListener(_onEventChanged);
    _onEventChanged();
  }

  @override
  void dispose() {
    widget.eventController.removeListener(_onEventChanged);
    super.dispose();
  }

  void _onEventChanged() {
    final key = widget.eventController.eventKey;
    if (key == _watchedEventKey) return;
    _watchedEventKey = key;
    if (key.isEmpty) return;
    unawaited(widget.shiftController?.watchEvent(key));

    unawaited(Future<void>.microtask(widget.eventController.loadForecasts));
  }

  NowSummary _summary() {
    final uid = widget.currentUid;
    final schedule = widget.shiftController?.schedule;
    return NowSummary.build(
      matches: widget.eventController.matches,
      myTeam: widget.eventController.myTeamNumber,
      entries: widget.scoutingController.entries,
      rotation: uid == null ? null : schedule?.rotationFor(uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.eventController;
    return AnimatedBuilder(
      animation: Listenable.merge([
        event,
        widget.scoutingController,
        widget.shiftController,
      ]),
      builder: (context, _) {
        if (!event.hasEvent) {
          return EmptyState(
            icon: Icons.event_outlined,
            message:
                'No event selected.\n'
                'Pick your event to see your next match and scouting shift.',
            actions: [
              FilledButton(
                onPressed: widget.onOpenSettings,
                child: const Text('Open Settings'),
              ),
            ],
          );
        }
        final summary = _summary();
        final match = _matchSection(context, summary);
        final shift = _shiftSection(context, summary);
        final alerts = _alertsSection(context, summary);
        final sections = widget.isLead
            ? [match, alerts, ?shift]
            : [?shift, match, alerts];
        final border = StrategyPalette.borderOf(context);
        final bottom = 16 + GlassChrome.bottomInsetOf(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, summary),
                    for (final section in sections) ...[
                      Divider(height: 1, color: border),
                      section,
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, NowSummary summary) {
    final event = widget.eventController;
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final played = summary.playedThrough;
    final status = widget.scoutingController.syncStatus;
    final offline = status.state == ScoutingSyncState.offline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.eventName.isNotEmpty ? event.eventName : event.eventKey,
            style: text.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            played == null
                ? 'No scouted matches yet'
                : 'Scouted through Q$played',
            style: text.bodySmall?.copyWith(color: muted),
          ),
          if (offline) ...[
            const SizedBox(height: 12),
            const _Notice(
              icon: Icons.cloud_off_rounded,
              text:
                  'Offline. New entries stay on this device and sync when '
                  'you are back online.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _matchSection(BuildContext context, NowSummary summary) {
    final event = widget.eventController;
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final next = summary.next;
    if (next == null) {
      return _Section(
        title: 'Our next match',
        children: [
          Text(_noMatchMessage(summary), style: text.bodyMedium),
          if (event.matches.isNotEmpty && event.myTeamNumber == null)
            _SectionAction(
              primary: widget.isLead,
              label: 'Open Settings',
              onPressed: widget.onOpenSettings,
            )
          else if (event.matches.isEmpty && !event.isLoading)
            _SectionAction(
              primary: false,
              label: 'Retry',
              onPressed: event.refresh,
            ),
        ],
      );
    }
    final awayText = _awayLabel(
      next.matchesAway,
      unknown: 'Progress unknown',
      now: 'Up next',
    );
    final chance = _winChance(next);
    return _Section(
      title: 'Our next match',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(next.match.displayName, style: text.titleLarge),
            const SizedBox(width: 12),
            Text(awayText, style: text.bodyMedium?.copyWith(color: muted)),
          ],
        ),
        if (chance != null)
          Text(chance, style: text.bodySmall?.copyWith(color: muted)),
        _AllianceTeams(
          caption: 'Partners',
          alliance: next.ourAlliance,
          teams: next.partners,
          onOpenTeam: widget.onOpenTeam,
        ),
        _AllianceTeams(
          caption: 'Opponents',
          alliance: next.opposingAlliance,
          teams: next.opponents,
          onOpenTeam: widget.onOpenTeam,
        ),
        _SectionAction(
          primary: widget.isLead,
          label: 'Prep',
          onPressed: () => widget.onPrepMatch(next.match),
        ),
      ],
    );
  }

  String _noMatchMessage(NowSummary summary) {
    final event = widget.eventController;
    final team = event.myTeamNumber;
    if (event.matches.isEmpty) {
      if (event.isLoading) return 'Loading the match schedule.';
      return event.scheduleError ??
          event.dataNotice ??
          'The match schedule for ${event.eventKey} is not out yet.';
    }
    if (team == null) {
      return 'Set your team number in Settings to see your next match.';
    }
    if (summary.ourQualCount == 0) {
      return 'Team $team is not on the qualification schedule.';
    }
    return 'Team $team has played all ${summary.ourQualCount} '
        'qualification matches.';
  }

  String? _winChance(NowMatch next) {
    final forecasts = widget.eventController.forecastsFor(next.match.key);
    if (forecasts.isEmpty) return null;
    final parts = <String>[];
    for (final forecast in forecasts) {
      final red = forecast.redWinProbability;
      final ours = next.ourAlliance == 'Red' ? red : 1 - red;
      parts.add('${forecast.source.label} ${(ours * 100).round()}%');
    }
    return 'Win chance: ${parts.join(', ')}';
  }

  Widget? _shiftSection(BuildContext context, NowSummary summary) {
    final controller = widget.shiftController;
    if (controller == null) return null;
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final shift = summary.shift;
    if (shift == null) {
      if (widget.isLead) return null;
      return _Section(
        title: 'Your scouting',
        children: [
          Text(
            controller.schedule == null
                ? 'No scouting shifts are set up for this event yet.'
                : 'No scouting shift is assigned to you.',
            style: text.bodyMedium,
          ),
          _SectionAction(
            primary: false,
            label: 'Open Scout',
            onPressed: widget.onOpenScout,
          ),
        ],
      );
    }
    final awayText = _awayLabel(
      summary.shiftMatchesAway,
      unknown: '',
      now: 'On duty now',
    );
    final range = shift.startMatch == shift.endMatch
        ? 'Q${shift.startMatch}'
        : 'Q${shift.startMatch} to Q${shift.endMatch}';
    return _Section(
      title: 'Your scouting',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(range, style: text.titleLarge),
            if (awayText.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(awayText, style: text.bodyMedium?.copyWith(color: muted)),
            ],
          ],
        ),
        _SectionAction(
          primary: !widget.isLead,
          label: 'Start',
          onPressed: widget.onOpenScout,
        ),
      ],
    );
  }

  Widget _alertsSection(BuildContext context, NowSummary summary) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final unconfirmed = widget.scoutingController.unconfirmedCount;
    final alerts = <Widget>[
      if (unconfirmed > 0)
        _AlertRow(
          icon: Icons.cloud_upload_outlined,
          text: unconfirmed == 1
              ? '1 scouting entry has not synced yet.'
              : '$unconfirmed scouting entries have not synced yet.',
          onTap: widget.onOpenScout,
        ),
      if (widget.isLead && summary.unscouted.isNotEmpty)
        _AlertRow(
          icon: Icons.visibility_off_outlined,
          text: _unscoutedText(summary),
          onTap: widget.onOpenDatabase,
        ),
    ];
    final clear = Text(
      'Nothing right now.',
      style: text.bodyMedium?.copyWith(color: muted),
    );
    return _Section(
      title: 'Needs attention',
      children: alerts.isEmpty ? [clear] : alerts,
    );
  }

  String _unscoutedText(NowSummary summary) {
    final robots = summary.unscoutedRobots;
    final labels = [for (final m in summary.unscouted) m.match.displayName];
    final shown = labels.take(3).join(', ');
    final more = labels.length > 3 ? ' and ${labels.length - 3} more' : '';
    final noun = robots == 1 ? 'robot' : 'robots';
    return '$robots $noun not scouted in $shown$more.';
  }
}

String _awayLabel(int? away, {required String unknown, required String now}) {
  if (away == null) return unknown;
  if (away == 0) return now;
  return away == 1 ? '1 match away' : '$away matches away';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleSmall;
    final style = base?.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: style)),
          for (final child in children) ...[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.primary,
    required this.label,
    required this.onPressed,
  });

  final bool primary;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);
    return Align(
      alignment: Alignment.centerLeft,
      child: primary
          ? FilledButton(onPressed: onPressed, child: text)
          : OutlinedButton(onPressed: onPressed, child: text),
    );
  }
}

class _AllianceTeams extends StatelessWidget {
  const _AllianceTeams({
    required this.caption,
    required this.alliance,
    required this.teams,
    required this.onOpenTeam,
  });

  final String caption;
  final String alliance;
  final List<int> teams;
  final ValueChanged<int> onOpenTeam;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = StrategyPalette.allianceColor(alliance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: text.bodySmall?.copyWith(
            color: StrategyPalette.mutedTextOf(context),
          ),
        ),
        Row(
          children: [
            Container(
              width: 44,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.all(
                  Radius.circular(StrategyPalette.radiusSm),
                ),
              ),
              child: Text(
                alliance,
                style: text.labelSmall?.copyWith(
                  color: StrategyPalette.onAlliance,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                children: [
                  for (final team in teams)
                    TextButton(
                      onPressed: () => onOpenTeam(team),
                      child: Text('$team'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      leading: Icon(icon, color: Theme.of(context).colorScheme.error),
      title: Text(text),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
