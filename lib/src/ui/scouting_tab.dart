import 'dart:convert';

import 'package:flutter/material.dart';

import '../scouting/models/accuracy_alert.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_schedule.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/services/scouting_sync_service.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/state/scout_drawing_controller.dart';
import '../scouting/state/scouting_controller.dart';
import '../scouting/ui/scout_form_fields.dart';
import '../scouting/ui/scout_qr_scan_screen.dart';
import '../scouting/ui/scout_qr_share_screen.dart';
import '../scouting/widgets/scout_drawing_canvas.dart';
import '../services/match_id_resolver.dart';

import 'package:statbotics_client/statbotics_client.dart';

import '../state/event_controller.dart';
import '../state/failed_write_tracker.dart';
import '../state/strategy_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/notice_row.dart';
import '../widgets/sync_status_pill.dart';
import 'event_picker_dialog.dart';

class ScoutingTab extends StatefulWidget {
  const ScoutingTab({
    required this.strategyController,
    required this.scoutingController,
    required this.configController,
    required this.eventController,
    super.key,
  });

  final StrategyController strategyController;
  final ScoutingController scoutingController;
  final ScoutConfigController configController;
  final EventController eventController;

  @override
  State<ScoutingTab> createState() => _ScoutingTabState();
}

class _ScoutingTabState extends State<ScoutingTab> {
  Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _textControllers = {};
  String? _statusMessage;

  final Map<String, int> _actionTrackerResetTokens = <String, int>{};
  String _configFingerprint = '';
  final ScoutDrawingController _drawingController = ScoutDrawingController();

  ScoutConfig get _config => widget.configController.config;
  EventController get _eventCtrl => widget.eventController;

  @override
  void initState() {
    super.initState();
    widget.configController.addListener(_onConfigChanged);
    _initValues(_config);
    _configFingerprint = jsonEncode(_config.toJson());
  }

  @override
  void dispose() {
    widget.configController.removeListener(_onConfigChanged);
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _drawingController.dispose();
    super.dispose();
  }

  void _onConfigChanged() {
    final fingerprint = jsonEncode(_config.toJson());
    if (fingerprint == _configFingerprint) return;
    _configFingerprint = fingerprint;
    setState(() {
      for (final c in _textControllers.values) {
        c.dispose();
      }
      _textControllers.clear();
      _initValues(_config);
    });
  }

  void _initValues(ScoutConfig config) {
    _values = {};
    for (final field in config.allFields) {
      _values[field.code] = field.effectiveDefault;

      if (field.type == ScoutFieldType.text ||
          field.type == ScoutFieldType.number ||
          field.type == ScoutFieldType.tbaMatchNumber) {
        final ctrl = TextEditingController(
          text: _values[field.code]?.toString() ?? '',
        );
        if (field.code == 'matchNumber') {
          ctrl.addListener(() {
            _values[field.code] = ctrl.text;
            _onMatchOrStationChanged();
          });
        } else {
          ctrl.addListener(() {
            _values[field.code] = ctrl.text;
          });
        }
        _textControllers[field.code] = ctrl;
      }
    }
  }

  void _onMatchOrStationChanged() {
    final team = _lookupTeamFromSchedule();
    if (team != null) {
      _values['pTnumber'] = team;
      _textControllers['pTnumber']?.text = team.toString();
    }
    _syncTbaTeamFields();
    setState(() {});
  }

  void _syncTbaTeamFields() {
    final fields = _config.allFields
        .where((f) => f.type == ScoutFieldType.tbaTeamAndRobot)
        .toList(growable: false);
    if (fields.isEmpty) return;
    final override = _values['robot']?.toString() ?? '';
    final matchNumber = int.tryParse(
      _values['matchNumber']?.toString().trim() ?? '',
    );
    final schedule = ScoutSchedule.fromMatches(_eventCtrl.matches);
    for (final field in fields) {
      final existing = _values[field.code];
      final station = override.isNotEmpty
          ? override
          : (existing is Map
                ? existing['robotPosition']?.toString() ?? ''
                : '');
      final robot = schedule.robotForStation(matchNumber, station);
      if (robot == null) continue;
      _values[field.code] = <String, dynamic>{
        'teamNumber': robot.team,
        'robotPosition': robot.position,
      };
    }
  }

  int? _lookupTeamFromSchedule() {
    final station = _values['robot']?.toString().trim() ?? '';
    if (station.isEmpty) return null;
    final match = _lookupScheduledMatch();
    if (match == null) return null;
    return match.teamForStation(station);
  }

  String? _lookupTbaMatchKey() {
    final match = _lookupScheduledMatch();
    final key = match?.key ?? '';
    return key.isNotEmpty ? key : null;
  }

  StatboticsMatch? _lookupScheduledMatch() {
    if (!_eventCtrl.hasMatches) return null;
    final typed = _values['matchNumber']?.toString().trim() ?? '';

    final candidates = MatchIdResolver(_eventCtrl.matches).candidates(typed);
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    final station = _values['robot']?.toString().trim() ?? '';
    final teamNumber = _extractTeamNumber();
    if (station.isNotEmpty) {
      if (teamNumber > 0) {
        final exactStationMatches = candidates
            .where((m) => m.teamForStation(station) == teamNumber)
            .toList(growable: false);
        if (exactStationMatches.length == 1) {
          return exactStationMatches.first;
        }
      }

      final stationMatches = candidates
          .where((m) => m.teamForStation(station) != null)
          .toList(growable: false);
      if (stationMatches.length == 1) {
        return stationMatches.first;
      }
    }

    if (teamNumber > 0) {
      final teamMatches = candidates
          .where((m) => m.allTeams.contains(teamNumber))
          .toList(growable: false);
      if (teamMatches.length == 1) {
        return teamMatches.first;
      }
    }

    debugPrint(
      'ScoutingTab: could not uniquely resolve schedule match for number '
      '"$typed" using station "$station" and team $teamNumber. '
      'Verify the match number, station, and team entry. '
      'Candidates: ${candidates.map((m) => m.key).join(', ')}',
    );
    return null;
  }

  void _setFieldValue(String code, dynamic value) {
    setState(() {
      _values[code] = value;

      final controller = _textControllers[code];
      if (controller != null && controller.text != (value?.toString() ?? '')) {
        controller.text = value?.toString() ?? '';
      }
      if (code == 'robot' || code == 'matchNumber') {
        final team = _lookupTeamFromSchedule();
        if (team != null) {
          _values['pTnumber'] = team;
          _textControllers['pTnumber']?.text = team.toString();
        }
        _syncTbaTeamFields();
      }
    });
  }

  void _applyReset() {
    setState(() {
      for (final field in _config.allFields) {
        if (field.type == ScoutFieldType.actionTracker) {
          if (field.formResetBehavior == ResetBehavior.reset) {
            for (final action in field.actions) {
              _values['${field.code}_${action.code}_count'] = 0;
              _values['${field.code}_${action.code}_times'] = '';
            }
            _actionTrackerResetTokens[field.code] =
                (_actionTrackerResetTokens[field.code] ?? 0) + 1;
          }
          continue;
        }

        if (field.type == ScoutFieldType.tbaTeamAndRobot &&
            field.formResetBehavior == ResetBehavior.increment) {
          _values[field.code] = field.effectiveDefault;
          continue;
        }
        switch (field.formResetBehavior) {
          case ResetBehavior.reset:
            _values[field.code] = field.effectiveDefault;
            _textControllers[field.code]?.text =
                field.effectiveDefault?.toString() ?? '';
          case ResetBehavior.preserve:
            break;
          case ResetBehavior.increment:
            final current =
                (num.tryParse(_values[field.code]?.toString() ?? '') ?? 0)
                    .toInt();
            _values[field.code] = current + 1;
            _textControllers[field.code]?.text = _values[field.code].toString();
        }
      }
      _statusMessage = null;
      _drawingController.clear();
    });
    final team = _lookupTeamFromSchedule();
    setState(() {
      if (team != null) {
        _values['pTnumber'] = team;
        _textControllers['pTnumber']?.text = team.toString();
      }

      _syncTbaTeamFields();
    });
  }

  int _extractTeamNumber() {
    for (final field in _config.allFields) {
      if (field.type != ScoutFieldType.tbaTeamAndRobot) continue;
      final value = _values[field.code];
      if (value is Map) {
        final team = value['teamNumber'];
        final n = (team is num) ? team.toInt() : int.tryParse('$team');
        if (n != null && n > 0) return n;
      }
    }
    for (final code in ['pTnumber', 'teamNumber', 'team', 'teamNum']) {
      final v = _values[code];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) return n;
      }
    }
    return 0;
  }

  Future<void> _saveEntry() async {
    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }

    final teamNumber = _extractTeamNumber();
    final session = widget.strategyController.session;

    final existing = widget.scoutingController.findEntry(
      matchId: session.id,
      teamNumber: teamNumber,
    );

    final tbaMatchKey = _lookupTbaMatchKey();

    final stationAlliances = _values.values
        .map(allianceFromStationValue)
        .whereType<String>()
        .toSet();

    final scoutedAlliance = stationAlliances.length == 1
        ? stationAlliances.first
        : session.alliance;

    final entry =
        (existing ??
                ScoutEntry(
                  matchId: session.id,
                  teamNumber: teamNumber,
                  alliance: scoutedAlliance,
                  tbaMatchKey: tbaMatchKey,
                ))
            .copyWith(
              fieldValues: Map<String, dynamic>.from(_values),
              alliance: scoutedAlliance,
              tbaMatchKey: tbaMatchKey ?? existing?.tbaMatchKey,
              strokesByPhase: _drawingController.isEmpty
                  ? null
                  : Map<String, dynamic>.from(_drawingController.toJson()),
            );

    final syncState = widget.scoutingController.syncStatus.state;
    final syncEnabled =
        syncState != ScoutingSyncState.signedOut &&
        syncState != ScoutingSyncState.noAccess;

    final saved = await widget.scoutingController.saveEntry(entry);
    if (!mounted) return;

    final teamLabel = teamNumber > 0 ? ' for team $teamNumber' : '';
    if (!saved) {
      setState(() {
        _statusMessage =
            widget.scoutingController.lastError ??
            'Could not save the entry$teamLabel. Nothing was recorded, so do '
                'not leave this screen yet.';
      });
      widget.scoutingController.clearLastError();
      return;
    }
    setState(() {
      _statusMessage = syncEnabled
          ? 'Entry$teamLabel saved and syncing to the team database. Tap "New match" to scout another team.'
          : 'Entry$teamLabel saved locally. Sign in via the account icon to auto-submit to the team database.';
    });

    _applyReset();
  }

  Future<void> _scanQr() async {
    final entry = await Navigator.of(context).push<ScoutEntry>(
      MaterialPageRoute<ScoutEntry>(
        builder: (_) => ScoutQrScanScreen(
          controller: widget.scoutingController,
          config: _config,
        ),
      ),
    );
    if (!mounted || entry == null) return;
    setState(() {
      _statusMessage =
          'Imported entry${entry.teamNumber > 0 ? ' for team ${entry.teamNumber}' : ''} from QR.';
    });
  }

  Future<void> _showQr(ScoutEntry entry) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScoutQrShareScreen(entry: entry, config: _config),
      ),
    );
  }

  Future<void> _confirmDeleteEntry(ScoutEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete entry?'),
          content: Text(
            entry.teamNumber > 0
                ? 'This will remove the entry for team ${entry.teamNumber}, '
                      'including from the shared database.'
                : 'This will remove the entry, including from the shared '
                      'database.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final deleted = await widget.scoutingController.deleteEntry(entry.id);
    if (!mounted || deleted) return;
    setState(() {
      _statusMessage =
          widget.scoutingController.lastError ??
          'Could not delete that entry. It is still saved on this device.';
    });
    widget.scoutingController.clearLastError();
  }

  Future<void> _selectEvent() async {
    await showEventPicker(context, _eventCtrl);
  }

  String _eventLinkMessage() {
    if (!_eventCtrl.hasEvent) {
      return 'No event selected. Entries cannot be linked to the match '
          'schedule, so accuracy checks are off.';
    }
    final eventLabel = _eventCtrl.eventName.isNotEmpty
        ? _eventCtrl.eventName
        : _eventCtrl.eventKey;
    if (!_eventCtrl.hasMatches) {
      return 'Scouting at $eventLabel. The match schedule has not loaded '
          'yet, so this entry will skip accuracy checks.';
    }
    final matchText = _values['matchNumber']?.toString().trim() ?? '';
    if (matchText.isEmpty) {
      return 'Scouting at $eventLabel. Enter a match number to link this '
          'entry to the schedule for accuracy checks.';
    }
    final match = _lookupScheduledMatch();
    if (match == null) {
      return 'Scouting at $eventLabel. Match $matchText is not in the '
          'schedule, so this entry will skip accuracy checks.';
    }
    return 'Scouting at $eventLabel. This entry links to ${match.key} '
        'for accuracy checks.';
  }

  String get _currentMatchDisplay {
    final num = _values['matchNumber']?.toString() ?? '';
    final station = _values['robot']?.toString() ?? '';
    if (num.isEmpty && station.isEmpty) return _config.title;
    final parts = <String>[_config.title];
    if (num.isNotEmpty) parts.add('Match $num');
    if (station.isNotEmpty) parts.add(station);
    return parts.join(' — ');
  }

  Widget _buildDrawingSection(BuildContext context) {
    final phase = _drawingController.selectedPhase;
    final tool = _drawingController.selectedTool;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report drawing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: StrategyPhase.values
                  .map(
                    (p) => ChoiceChip(
                      label: Text(p.label),
                      selected: phase == p,
                      selectedColor: StrategyPalette.phaseColor(p)
                          .withValues(alpha: 0.8),
                      onSelected: (selected) {
                        if (selected) {
                          _drawingController.selectedPhase = p;
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ToolButton(
                  tool: StrategyTool.draw,
                  icon: Icons.draw_rounded,
                  label: 'Draw',
                  selected: tool == StrategyTool.draw,
                  onTap: () {
                    _drawingController.selectedTool = StrategyTool.draw;
                  },
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  tool: StrategyTool.delete,
                  icon: Icons.backspace_rounded,
                  label: 'Erase',
                  selected: tool == StrategyTool.delete,
                  onTap: () {
                    _drawingController.selectedTool = StrategyTool.delete;
                  },
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _drawingController.isEmpty
                      ? null
                      : () => _drawingController.clear(),
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ScoutDrawingCanvas(controller: _drawingController),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SaveShortcut(
      onSave: _saveEntry,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          widget.strategyController,
          widget.scoutingController,
          widget.configController,
          widget.eventController,
        ]),
        builder: (context, _) {
          final session = widget.strategyController.session;
          final entries = widget.scoutingController.entriesForMatch(session.id);

          final pendingAlerts = widget.scoutingController.pendingAlerts;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pendingAlerts.isNotEmpty)
                _AccuracyAlertBanner(
                  alerts: pendingAlerts,
                  onDismissAll: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    var failures = 0;
                    for (final alert in pendingAlerts) {
                      try {
                        await widget.scoutingController.acknowledgeAlert(
                          alert.entryId,
                        );
                      } catch (_) {
                        failures++;
                      }
                      if (!mounted) return;
                    }
                    if (failures > 0) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not dismiss $failures alert'
                            '${failures == 1 ? '' : 's'}. They will come back '
                            'until the acknowledgment reaches the database.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              Row(
                children: [
                  Expanded(
                    child: _SyncStatusPill(
                      status: widget.scoutingController.syncStatus,
                      failedWrites: widget.scoutingController.failedWrites,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _scanQr,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan QR'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.scoutingController.syncStatus.state ==
                      ScoutingSyncState.signedOut ||
                  widget.scoutingController.syncStatus.state ==
                      ScoutingSyncState.noAccess)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: StrategyPalette.surfaceOf(context),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.scoutingController.syncStatus.state ==
                                      ScoutingSyncState.noAccess
                                  ? 'Auto-submit is off. Your account has no team access yet; ask an admin to approve it.'
                                  : 'Auto-submit is off. Tap the account icon at the top to sign in and send entries directly to the team database.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  color: StrategyPalette.surfaceOf(context),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: NoticeRow(
                      icon: _eventCtrl.hasEvent
                          ? Icons.event_available_rounded
                          : Icons.event_busy_rounded,
                      message: _eventLinkMessage(),
                      messageStyle: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                      action: TextButton(
                        onPressed: _selectEvent,
                        child: Text(
                          _eventCtrl.hasEvent ? 'Change' : 'Select event',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentMatchDisplay,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ..._config.sections.map(
                (section) => ScoutFormSection(
                  section: section,
                  keyPrefix: 'scout-field',
                  values: _values,
                  textControllers: _textControllers,
                  onFieldChanged: _setFieldValue,
                  actionTrackerResetTokens: _actionTrackerResetTokens,
                  schedule: ScoutSchedule.fromMatches(_eventCtrl.matches),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _drawingController,
                builder: (context, _) => _buildDrawingSection(context),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saveEntry,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save entry'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _applyReset,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('New match'),
                  ),
                ],
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_statusMessage!),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Saved this match',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (entries.isEmpty)
                        const Text('No entries saved yet for this match.')
                      else
                        ...entries.map(
                          (entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              entry.teamNumber > 0
                                  ? 'Team ${entry.teamNumber}'
                                  : 'Entry',
                            ),
                            subtitle: Text(
                              '${entry.fieldValues.length} fields recorded',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.qr_code_2_rounded),
                                  tooltip: 'Show QR',
                                  onPressed: () => _showQr(entry),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  tooltip: 'Delete entry',
                                  onPressed: () => _confirmDeleteEntry(entry),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccuracyAlertBanner extends StatelessWidget {
  const _AccuracyAlertBanner({
    required this.alerts,
    required this.onDismissAll,
  });

  final List<AccuracyAlert> alerts;
  final VoidCallback onDismissAll;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = alerts.length;
    final label = count == 1
        ? '1 entry may have inaccurate data. Please review and re-scout if needed.'
        : '$count entries may have inaccurate data. Please review and re-scout if needed.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: StrategyPalette.surfaceStrongOf(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_rounded, size: 16, color: colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...alerts.map(
                      (alert) => Text(
                        'Team ${alert.teamNumber} — ${alert.tbaMatchKey}: '
                        '${alert.flaggedFields.map((f) => f.fieldCode).join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colorScheme.error,
                ),
                tooltip: 'Dismiss',
                onPressed: onDismissAll,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final StrategyTool tool;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : null,
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outline,
        ),
      ),
    );
  }
}

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({required this.status, required this.failedWrites});

  final ScoutingSyncStatus status;

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    if (failedWrites.hasFailures) {
      final count = failedWrites.unlandedCount;
      return SyncStatusPill(
        label: '$count edit${count == 1 ? '' : 's'} not saved',
        icon: Icons.cloud_off_rounded,
        isFailure: true,
      );
    }

    final (String label, IconData icon) = switch (status.state) {
      ScoutingSyncState.signedOut => (
        'Not signed in to sync',
        Icons.cloud_off_rounded,
      ),
      ScoutingSyncState.noAccess => (
        'No team access yet',
        Icons.lock_outline_rounded,
      ),
      ScoutingSyncState.syncing => ('Syncing...', Icons.sync_rounded),
      ScoutingSyncState.synced => ('Synced', Icons.cloud_done_rounded),
      ScoutingSyncState.offline => ('Offline', Icons.cloud_off_rounded),
    };

    return SyncStatusPill(label: label, icon: icon);
  }
}
