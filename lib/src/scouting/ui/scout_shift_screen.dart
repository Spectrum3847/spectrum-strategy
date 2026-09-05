import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../models/user_role.dart';
import '../../services/local_only_services.dart';
import '../../services/name_list_parse.dart';
import '../../state/event_controller.dart';
import '../../state/failed_write_tracker.dart';
import '../../state/user_role_controller.dart';
import '../../theme/strategy_palette.dart';
import '../../widgets/sync_status_pill.dart';
import '../models/scout_shift_schedule.dart';
import '../models/shift_trade.dart';
import '../state/scout_shift_controller.dart';
import '../state/shift_trade_controller.dart';
import 'scout_shift_grid.dart';

class ScoutShiftScreen extends StatefulWidget {
  const ScoutShiftScreen({
    required this.eventController,
    required this.userRoleController,
    ScoutShiftController? controller,
    this.tradeController,
    super.key,
  }) : injectedController = controller;

  final EventController eventController;
  final UserRoleController userRoleController;

  final ScoutShiftController? injectedController;

  final ShiftTradeController? tradeController;

  @override
  State<ScoutShiftScreen> createState() => _ScoutShiftScreenState();
}

class _ScoutShiftScreenState extends State<ScoutShiftScreen> {
  late final ScoutShiftController _controller;
  String? _watchedEventKey;

  Map<String, String> _uidByName = const <String, String>{};
  Map<String, int> _nameCounts = const <String, int>{};

  bool _profilesLoaded = false;

  bool get _canGenerate => widget.userRoleController.roles.canEditAnyEntry;
  String? get _uid => widget.userRoleController.currentUid;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.injectedController ??
        ScoutShiftController(syncService: LocalOnlyScoutShiftSyncService());

    unawaited(widget.tradeController?.bootstrap());
    unawaited(_loadProfiles());
    widget.eventController.addListener(_onEventChanged);
    _onEventChanged();
  }

  Future<void> _loadProfiles() async {
    List<UserProfile> profiles = const <UserProfile>[];
    var loaded = true;
    try {
      profiles = await widget.userRoleController.streamAllProfiles().first;
    } catch (_) {
      loaded = false;
    }
    final counts = <String, int>{};
    for (final p in profiles) {
      if (p.displayName.isEmpty) continue;
      final key = p.displayName.trim().toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _nameCounts = counts;
      _uidByName = <String, String>{
        for (final p in profiles)
          if (p.displayName.isNotEmpty &&
              counts[p.displayName.trim().toLowerCase()] == 1)
            p.displayName.trim().toLowerCase(): p.uid,
      };
      _profilesLoaded = loaded;
    });
  }

  void _onEventChanged() {
    final key = widget.eventController.eventKey;
    if (key == _watchedEventKey) return;
    _watchedEventKey = key;
    _controller.watchEvent(key);
    widget.tradeController?.watchEvent(key);
  }

  @override
  void dispose() {
    widget.eventController.removeListener(_onEventChanged);

    if (widget.injectedController == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  int get _qualMatchCount =>
      widget.eventController.matches.where((m) => m.compLevel == 'qm').length;

  Future<void> _openInputNamesDialog() async {
    final schedule = _controller.schedule;
    if (schedule != null && !schedule.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Regenerate the shift rotation?'),
          content: const Text(
            'This replaces the current grid for everyone on the roster, '
            'including any manual edits. Anyone relying on their existing '
            'shifts will see the new ones instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;

    if (!_profilesLoaded) await _loadProfiles();
    if (!mounted) return;

    final result = await showDialog<_InputNamesResult>(
      context: context,
      builder: (context) => _InputNamesDialog(
        initialNames: schedule?.roster.map((r) => r.name).join('\n') ?? '',
        initialMatchCount: schedule?.matchCount ?? _qualMatchCount,
      ),
    );
    if (result == null || result.names.isEmpty || !mounted) return;

    final ambiguousNames = <String>{};
    final unmatchedNames = <String>{};
    final roster = [
      for (final name in result.names)
        ScoutShiftRosterEntry(
          uid: _resolveTypedName(name, ambiguousNames, unmatchedNames),
          name: name,
        ),
    ];
    await _controller.generate(matchCount: result.matchCount, roster: roster);
    if (!mounted) return;
    _reportUnlinkedNames(ambiguousNames, unmatchedNames);
  }

  void _reportUnlinkedNames(
    Set<String> ambiguousNames,
    Set<String> unmatchedNames,
  ) {
    final problems = <String>[
      if (!_profilesLoaded)
        'The member list could not be loaded, so no name on this roster is '
            'linked to an account.',
      if (unmatchedNames.isNotEmpty)
        'No matching account: ${unmatchedNames.join(', ')}. Each name has to '
            'match that member\'s account name exactly.',
      if (ambiguousNames.isNotEmpty)
        'Name shared by several members: ${ambiguousNames.join(', ')}.',
    ];
    if (problems.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${problems.join(' ')} Those scouters cannot see their own shifts '
          'or request a trade until the names are fixed.',
        ),
        duration: const Duration(seconds: 10),
      ),
    );
  }

  String _resolveTypedName(
    String name,
    Set<String> ambiguousNames,
    Set<String> unmatchedNames,
  ) {
    final key = name.trim().toLowerCase();
    if ((_nameCounts[key] ?? 0) > 1) {
      ambiguousNames.add(name);
      return '';
    }
    final uid = _uidByName[key];
    if (uid == null && _profilesLoaded) unmatchedNames.add(name);
    return uid ?? '';
  }

  String? _renamedColumnUid(String name) {
    if (!_profilesLoaded) return null;
    final key = name.trim().toLowerCase();
    if ((_nameCounts[key] ?? 0) > 1) return '';
    return _uidByName[key] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scout shifts')),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          widget.eventController,
          _controller,
          if (widget.tradeController != null) widget.tradeController!,
        ]),
        builder: (context, _) {
          if (!widget.eventController.hasMatches) {
            return const _Empty(
              message:
                  'Select an event with a match schedule to generate shifts.',
            );
          }
          final rawSchedule = _controller.schedule;
          if (rawSchedule == null || rawSchedule.isEmpty) {
            return _Empty(
              message: _canGenerate
                  ? 'No schedule yet. Tap "Input names" to build one.'
                  : 'No schedule yet. Ask a strategy lead to generate one.',
              action: _canGenerate
                  ? FilledButton.icon(
                      onPressed: widget.eventController.hasMatches
                          ? _openInputNamesDialog
                          : null,
                      icon: const Icon(Icons.autorenew_rounded),
                      label: const Text('Input names'),
                    )
                  : null,
            );
          }

          final schedule =
              widget.tradeController?.effectiveSchedule(rawSchedule) ??
              rawSchedule;

          final mine = _uid == null ? null : schedule.rotationFor(_uid!);
          final myTrades = widget.tradeController != null && _uid != null
              ? widget.tradeController!.pendingTradesFor(_uid!)
              : const <ShiftTrade>[];
          final tradedBlockSources =
              widget.tradeController != null && _uid != null
              ? _tradedBlockSourcesFor(
                  widget.tradeController!.acceptedTradesFor(_uid!),
                  _uid!,
                )
              : const <_BlockKey, String>{};

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Column(
                      children: [
                        if (_controller.failedWrites.hasFailures) ...[
                          _ScoutShiftSyncPill(
                            failedWrites: _controller.failedWrites,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.tradeController?.failedWrites.hasFailures ??
                            false) ...[
                          _ShiftTradeSyncPill(
                            failedWrites: widget.tradeController!.failedWrites,
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (mine == null &&
                            _uid != null &&
                            widget.tradeController != null &&
                            schedule.roster.any((r) => r.uid.isEmpty)) ...[
                          const _UnlinkedAccountNotice(),
                          const SizedBox(height: 16),
                        ],
                        if (mine != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Your shifts',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              if (widget.tradeController != null &&
                                  mine.shifts.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () =>
                                      _openRequestTradeSheet(schedule, mine),
                                  icon: const Icon(Icons.swap_horiz_rounded),
                                  label: const Text('Request trade'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _RotationCard(
                            rotation: mine,
                            highlight: true,
                            tradedBlockSources: tradedBlockSources,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (myTrades.isNotEmpty) ...[
                          _TradeRequestsSection(
                            trades: myTrades,
                            currentUid: _uid!,
                            onAccept: (trade) => _resolveTrade(
                              trade,
                              widget.tradeController!.accept(trade),
                              'Trade accepted -- your shifts updated.',
                            ),
                            onDecline: (trade) => _resolveTrade(
                              trade,
                              widget.tradeController!.decline(trade),
                              'Trade declined.',
                            ),
                            onCancel: (trade) => _resolveTrade(
                              trade,
                              widget.tradeController!.cancel(trade),
                              'Trade request cancelled.',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Schedule (${schedule.matchCount} qual matches)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (_canGenerate)
                      OutlinedButton.icon(
                        onPressed: widget.eventController.hasMatches
                            ? _openInputNamesDialog
                            : null,
                        icon: const Icon(Icons.autorenew_rounded),
                        label: const Text('Input names'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ScoutShiftGrid(
                    schedule: schedule,
                    canEdit: _canGenerate,
                    onCellEdit: (col, match, text, color) =>
                        _controller.editCell(
                          col: col,
                          match: match,
                          text: text,
                          color: color,
                        ),
                    onRenameColumn: (col, name) => _controller.renameColumn(
                      col,
                      name,
                      uid: _renamedColumnUid(name),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRequestTradeSheet(
    ScoutShiftSchedule schedule,
    ScouterShiftRotation mine,
  ) async {
    final tradeController = widget.tradeController;
    if (tradeController == null) return;
    final result = await showModalBottomSheet<_TradeRequestResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _RequestTradeSheet(
        schedule: schedule,
        mine: mine,
        currentUid: _uid ?? '',
      ),
    );
    if (result == null) return;
    await tradeController.requestTrade(
      targetUid: result.targetUid,
      targetDisplayName: result.targetDisplayName,
      requesterBlock: result.requesterBlock,
    );
  }

  Future<void> _resolveTrade(
    ShiftTrade trade,
    Future<void> op,
    String message,
  ) async {
    await op;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

typedef _BlockKey = (int startMatch, int endMatch);

_BlockKey _keyOf(ScoutShiftBlock block) => (block.startMatch, block.endMatch);

Map<_BlockKey, String> _tradedBlockSourcesFor(
  List<ShiftTrade> acceptedTrades,
  String uid,
) {
  final sources = <_BlockKey, String>{};
  for (final trade in acceptedTrades) {
    if (trade.requesterUid == uid) {
      final targetBlock = trade.targetBlock;
      if (targetBlock != null) {
        sources[_keyOf(targetBlock)] = trade.targetDisplayName;
      }
    } else if (trade.targetUid == uid) {
      sources[_keyOf(trade.requesterBlock)] = trade.requesterDisplayName;
    }
  }
  return sources;
}

class _TradeRequestResult {
  const _TradeRequestResult({
    required this.targetUid,
    required this.targetDisplayName,
    required this.requesterBlock,
  });

  final String targetUid;
  final String targetDisplayName;
  final ScoutShiftBlock requesterBlock;
}

class _UnlinkedAccountNotice extends StatelessWidget {
  const _UnlinkedAccountNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.link_off_rounded, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No column on this rotation is linked to your account, so '
                'your shifts are not highlighted and you cannot request a '
                'trade. Ask a strategy lead to check the spelling of your '
                'name on the grid against your account name.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoutShiftSyncPill extends StatelessWidget {
  const _ScoutShiftSyncPill({required this.failedWrites});

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    final count = failedWrites.unlandedCount;
    return SyncStatusPill(
      label: '$count edit${count == 1 ? '' : 's'} not saved',
      icon: Icons.cloud_off_rounded,
      isFailure: true,
    );
  }
}

class _RotationCard extends StatelessWidget {
  const _RotationCard({
    required this.rotation,
    required this.highlight,
    this.tradedBlockSources = const <_BlockKey, String>{},
  });

  final ScouterShiftRotation rotation;
  final bool highlight;

  final Map<_BlockKey, String> tradedBlockSources;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlight ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rotation.name.isEmpty ? '(no name)' : rotation.name,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (rotation.shifts.isEmpty)
              Text(
                'No on-duty matches',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final shift in rotation.shifts)
                    Builder(
                      builder: (context) {
                        final tradedWith = tradedBlockSources[_keyOf(shift)];
                        final label = shift.startMatch == shift.endMatch
                            ? 'Match ${shift.startMatch}'
                            : 'Matches ${shift.startMatch}–${shift.endMatch}';
                        final chip = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(StrategyPalette.radiusSm),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (tradedWith != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                              ],
                            ],
                          ),
                        );
                        return tradedWith == null
                            ? chip
                            : Tooltip(
                                message: 'Traded with $tradedWith',
                                child: chip,
                              );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InputNamesResult {
  const _InputNamesResult({required this.names, required this.matchCount});
  final List<String> names;
  final int matchCount;
}

class _InputNamesDialog extends StatefulWidget {
  const _InputNamesDialog({
    required this.initialNames,
    required this.initialMatchCount,
  });

  final String initialNames;
  final int initialMatchCount;

  @override
  State<_InputNamesDialog> createState() => _InputNamesDialogState();
}

class _InputNamesDialogState extends State<_InputNamesDialog> {
  static const int _maxMatchCount = ScoutShiftSchedule.kMaxMatchCount;

  late final TextEditingController _namesController = TextEditingController(
    text: widget.initialNames,
  );
  late final TextEditingController _matchCountController =
      TextEditingController(
        text: widget.initialMatchCount > 0 ? '${widget.initialMatchCount}' : '',
      );
  String? _matchCountError;

  @override
  void dispose() {
    _namesController.dispose();
    _matchCountController.dispose();
    super.dispose();
  }

  void _submit() {
    final names = parsePastedNames(_namesController.text);
    final matchCount = int.tryParse(_matchCountController.text.trim()) ?? 0;
    if (matchCount > _maxMatchCount) {
      setState(() => _matchCountError = 'Cannot be more than $_maxMatchCount');
      return;
    }
    if (names.isEmpty || matchCount <= 0) return;
    Navigator.of(context)
        .pop(_InputNamesResult(names: names, matchCount: matchCount));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Input names'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'One name per line, or paste a list separated by commas or '
              'tabs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _namesController,
              maxLines: 8,
              minLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ada Lovelace\nGrace Hopper\n...',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _matchCountController,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (_matchCountError != null) {
                  setState(() => _matchCountError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Qualification match count',
                border: const OutlineInputBorder(),
                errorText: _matchCountError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Generate')),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.action});
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _ShiftTradeSyncPill extends StatelessWidget {
  const _ShiftTradeSyncPill({required this.failedWrites});

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    final count = failedWrites.unlandedCount;
    return SyncStatusPill(
      label: '$count trade action${count == 1 ? '' : 's'} not saved',
      icon: Icons.cloud_off_rounded,
      isFailure: true,
    );
  }
}

class _TradeRequestsSection extends StatelessWidget {
  const _TradeRequestsSection({
    required this.trades,
    required this.currentUid,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  final List<ShiftTrade> trades;
  final String currentUid;
  final ValueChanged<ShiftTrade> onAccept;
  final ValueChanged<ShiftTrade> onDecline;
  final ValueChanged<ShiftTrade> onCancel;

  static const double _maxListHeight = 320;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Trade requests',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Chip(label: Text('${trades.length} pending')),
          ],
        ),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxListHeight),
            child: ListView.builder(
              key: const ValueKey('trade_requests_list'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: trades.length,
              itemBuilder: (context, index) {
                final trade = trades[index];
                return _ShiftTradeCard(
                  trade: trade,
                  currentUid: currentUid,
                  onAccept: () => onAccept(trade),
                  onDecline: () => onDecline(trade),
                  onCancel: () => onCancel(trade),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftTradeCard extends StatelessWidget {
  const _ShiftTradeCard({
    required this.trade,
    required this.currentUid,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  final ShiftTrade trade;
  final String currentUid;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isTarget = trade.targetUid == currentUid;
    final counterpartyName = isTarget
        ? trade.requesterDisplayName
        : trade.targetDisplayName;
    final block = trade.requesterBlock;
    final rangeLabel = block.startMatch == block.endMatch
        ? 'match ${block.startMatch}'
        : 'matches ${block.startMatch}–${block.endMatch}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTarget
                  ? '${counterpartyName.isEmpty ? '(no name)' : counterpartyName} '
                        'asked you to cover $rangeLabel'
                  : 'You asked ${counterpartyName.isEmpty ? '(no name)' : counterpartyName} '
                        'to cover $rangeLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: isTarget
                  ? [
                      TextButton(
                        onPressed: onDecline,
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: onAccept,
                        child: const Text('Accept'),
                      ),
                    ]
                  : [
                      TextButton(
                        onPressed: onCancel,
                        child: const Text('Cancel'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTradeSheet extends StatefulWidget {
  const _RequestTradeSheet({
    required this.schedule,
    required this.mine,
    required this.currentUid,
  });

  final ScoutShiftSchedule schedule;
  final ScouterShiftRotation mine;
  final String currentUid;

  @override
  State<_RequestTradeSheet> createState() => _RequestTradeSheetState();
}

class _RequestTradeSheetState extends State<_RequestTradeSheet> {
  ScoutShiftBlock? _block;
  ScoutShiftRosterEntry? _target;

  @override
  void initState() {
    super.initState();
    _block = widget.mine.shifts.isEmpty ? null : widget.mine.shifts.first;
  }

  @override
  Widget build(BuildContext context) {
    final others = widget.schedule.roster
        .where((r) => r.uid.isNotEmpty && r.uid != widget.currentUid)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request a trade',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Which of your shifts?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final block in widget.mine.shifts)
                  ChoiceChip(
                    label: Text(
                      block.startMatch == block.endMatch
                          ? 'Match ${block.startMatch}'
                          : 'Matches ${block.startMatch}–${block.endMatch}',
                    ),
                    selected: _block == block,
                    onSelected: (_) => setState(() => _block = block),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Ask who?', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<ScoutShiftRosterEntry>(
              initialValue: _target,
              items: [
                for (final entry in others)
                  DropdownMenuItem(
                    value: entry,
                    child: Text(entry.name.isEmpty ? '(no name)' : entry.name),
                  ),
              ],
              onChanged: (entry) => setState(() => _target = entry),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _block == null || _target == null
                    ? null
                    : () => Navigator.of(context).pop(
                        _TradeRequestResult(
                          targetUid: _target!.uid,
                          targetDisplayName: _target!.name,
                          requesterBlock: _block!,
                        ),
                      ),
                child: const Text('Send request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
