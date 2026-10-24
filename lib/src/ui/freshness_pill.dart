import 'dart:async';

import 'package:flutter/material.dart';

import '../models/data_freshness.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../state/event_controller.dart';
import '../state/pick_list_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/glass_modal.dart';

const double _kPillLabelMinWidth = 480;

DataFreshness freshnessOf({
  required ScoutingController scouting,
  required EventController event,
  PitScoutingController? pitScouting,
  PickListController? pickLists,
  required DateTime now,
}) {
  final status = scouting.syncStatus;
  final unsynced = scouting.unconfirmedCount;
  final scoutingLine = _syncLine(
    state: status.state.name,
    at: status.lastSyncedAt,
    now: now,
    whenSynced: 'Connected',
  );
  final pit = pitScouting?.syncStatus;
  final lists = pickLists?.syncStatus;
  return DataFreshness(
    headline: scoutingLine.headline,
    unsynced: unsynced,
    rejected: scouting.rejectedCount,
    sources: <FreshnessSource>[
      FreshnessSource(
        name: 'Scouting entries',
        status: scoutingLine.status,
        level: scoutingLine.level,
        updatedAt: status.lastSyncedAt,
      ),
      _eventSource(event),
      if (pit != null)
        _sourceFrom('Pit scouting', pit.state.name, pit.lastSyncedAt, now),
      if (lists != null)
        _sourceFrom('Pick lists', lists.state.name, lists.lastSyncedAt, now),
    ],
  );
}

FreshnessSource _eventSource(EventController event) {
  if (!event.hasEvent) {
    return const FreshnessSource(
      name: 'Event data (TBA, Statbotics)',
      status: 'No event selected',
      level: FreshnessLevel.idle,
    );
  }
  final (status, level) = event.isLoading
      ? ('Refreshing', FreshnessLevel.idle)
      : event.error != null
      ? ('Last refresh failed, showing saved data', FreshnessLevel.attention)
      : ('Loaded', FreshnessLevel.ok);
  return FreshnessSource(
    name: 'Event data (TBA, Statbotics)',
    status: status,
    level: level,
    updatedAt: event.dataFetchedAt,
  );
}

FreshnessSource _sourceFrom(
  String name,
  String state,
  DateTime? at,
  DateTime now,
) {
  final line = _syncLine(state: state, at: at, now: now, whenSynced: 'Synced');
  return FreshnessSource(
    name: name,
    status: line.status,
    level: line.level,
    updatedAt: at,
  );
}

({String headline, String status, FreshnessLevel level}) _syncLine({
  required String state,
  required DateTime? at,
  required DateTime now,
  required String whenSynced,
}) {
  final age = shortAgo(at, now);
  return switch (state) {
    'synced' => (
      headline: age.isEmpty ? 'Synced' : 'Synced $age',
      status: whenSynced,
      level: FreshnessLevel.ok,
    ),
    'syncing' => (
      headline: 'Syncing',
      status: 'Syncing now',
      level: FreshnessLevel.idle,
    ),
    'offline' => (
      headline: 'Offline',
      status: 'No connection. Changes send when you are back online.',
      level: FreshnessLevel.attention,
    ),
    'rejected' => (
      headline: 'Sync blocked',
      status: 'The server refused a write.',
      level: FreshnessLevel.attention,
    ),
    'noAccess' => (
      headline: 'No access',
      status: 'Signed in, but this account has no role yet.',
      level: FreshnessLevel.attention,
    ),
    _ => (
      headline: 'Local only',
      status: 'Not signed in. Data stays on this device.',
      level: FreshnessLevel.idle,
    ),
  };
}

IconData _iconFor(FreshnessLevel level) => switch (level) {
  FreshnessLevel.ok => Icons.cloud_done_outlined,
  FreshnessLevel.idle => Icons.cloud_outlined,
  FreshnessLevel.attention => Icons.cloud_off_outlined,
};

class FreshnessPill extends StatefulWidget {
  const FreshnessPill({
    required this.scoutingController,
    required this.eventController,
    this.pitScoutingController,
    this.pickListController,
    this.clock,
    super.key,
  });

  final ScoutingController scoutingController;
  final EventController eventController;
  final PitScoutingController? pitScoutingController;
  final PickListController? pickListController;

  final DateTime Function()? clock;

  @override
  State<FreshnessPill> createState() => _FreshnessPillState();
}

class _FreshnessPillState extends State<FreshnessPill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();

    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Listenable get _listenable => Listenable.merge(<Listenable?>[
    widget.scoutingController,
    widget.eventController,
    widget.pitScoutingController,
    widget.pickListController,
  ]);

  DataFreshness _freshness() => freshnessOf(
    scouting: widget.scoutingController,
    event: widget.eventController,
    pitScouting: widget.pitScoutingController,
    pickLists: widget.pickListController,
    now: (widget.clock ?? DateTime.now)(),
  );

  void _open() {
    unawaited(
      showGlassModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _FreshnessSheet(
          listenable: _listenable,
          freshness: _freshness,
          now: widget.clock ?? DateTime.now,
          onSyncNow: widget.scoutingController.syncNow,
          onRefreshEvent: widget.eventController.hasEvent
              ? widget.eventController.refresh
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= _kPillLabelMinWidth;
    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        final freshness = _freshness();
        final attention = freshness.level == FreshnessLevel.attention;
        final ink = attention ? scheme.error : scheme.onSurface;
        final label = wide
            ? freshness.pillLabel
            : (freshness.unsynced > 0 ? '${freshness.unsynced}' : '');
        return Semantics(
          button: true,
          label: 'Data status: ${freshness.pillLabel}. Tap for details.',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: scheme.secondary,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: attention ? scheme.error : scheme.outline,
                ),
                borderRadius: const BorderRadius.all(
                  Radius.circular(StrategyPalette.radiusSm),
                ),
              ),
              child: InkWell(
                onTap: _open,
                borderRadius: const BorderRadius.all(
                  Radius.circular(StrategyPalette.radiusSm),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    minWidth: 44,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_iconFor(freshness.level), size: 18, color: ink),
                        if (label.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            label,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: ink),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FreshnessSheet extends StatelessWidget {
  const _FreshnessSheet({
    required this.listenable,
    required this.freshness,
    required this.now,
    required this.onSyncNow,
    required this.onRefreshEvent,
  });

  final Listenable listenable;
  final DataFreshness Function() freshness;
  final DateTime Function() now;
  final Future<void> Function() onSyncNow;
  final Future<void> Function()? onRefreshEvent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final border = StrategyPalette.borderOf(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: AnimatedBuilder(
          animation: listenable,
          builder: (context, _) {
            final data = freshness();
            final at = now();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Is my data up to date?',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(data.answer, style: text.bodyMedium),
                const SizedBox(height: 12),
                for (final source in data.sources) ...[
                  Divider(height: 1, color: border),
                  _SourceRow(source: source, now: at),
                ],
                Divider(height: 1, color: border),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => unawaited(onSyncNow()),
                      child: const Text('Sync now'),
                    ),
                    if (onRefreshEvent != null)
                      OutlinedButton(
                        onPressed: () => unawaited(onRefreshEvent!()),
                        child: const Text('Refresh event data'),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.now});

  final FreshnessSource source;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = StrategyPalette.mutedTextOf(context);
    final attention = source.level == FreshnessLevel.attention;
    final ink = attention ? Theme.of(context).colorScheme.error : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(source.level), size: 20, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    source.status,
                    style: text.bodySmall?.copyWith(color: ink ?? muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              source.updatedAt == null
                  ? 'No update yet'
                  : 'Updated ${longAgo(source.updatedAt, now)}',
              style: text.bodySmall?.copyWith(color: muted),
              textAlign: TextAlign.end,
            ),
          ],
        ),
      ),
    );
  }
}
