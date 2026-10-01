import 'dart:async';

import 'package:flutter/material.dart';

import '../models/action_tracker.dart';
import '../models/scout_config.dart';

class ActionTrackerField extends StatefulWidget {
  const ActionTrackerField({
    required this.field,
    required this.onFieldChanged,
    this.resetToken = 0,
    super.key,
  });

  final int resetToken;

  final ScoutConfigField field;

  final void Function(String code, dynamic value) onFieldChanged;

  @override
  State<ActionTrackerField> createState() => _ActionTrackerFieldState();
}

class _ActionTrackerFieldState extends State<ActionTrackerField> {
  late ActionTrackerLog _log = ActionTrackerLog.empty(widget.field.code);
  Stopwatch? _stopwatch;
  Timer? _ticker;

  final Map<String, double> _pressedAt = <String, double>{};

  bool get _isHold => widget.field.trackerMode == ActionTrackerMode.hold;
  bool get _running => _stopwatch?.isRunning ?? false;
  double get _elapsed => (_stopwatch?.elapsedMilliseconds ?? 0) / 1000;

  @override
  void didUpdateWidget(ActionTrackerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _reset();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _autoStopped = false;

  void _start() {
    if (_autoStopped) {
      return;
    }
    setState(() {
      _stopwatch = (_stopwatch ?? Stopwatch())..start();
    });
    _ticker?.cancel();

    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final stop = widget.field.autoStopSeconds;
      if (stop != null && _elapsed >= stop) {
        _autoStopped = true;
        _stop();
        return;
      }
      setState(() {});
    });
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;

    for (final code in _pressedAt.keys.toList()) {
      _endPress(code);
    }
    setState(() => _stopwatch?.stop());
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _pressedAt.clear();
    setState(() {
      _stopwatch = null;
      _autoStopped = false;
      _log = _log.clear();
    });
    _publish();
  }

  void _tap(String actionCode) {
    if (!_running) return;
    setState(() {
      _log = _log.add(ActionTrackerEvent(actionCode: actionCode, at: _elapsed));
    });
    _publish();
  }

  void _beginPress(String actionCode) {
    if (!_running) return;
    _pressedAt[actionCode] = _elapsed;
  }

  void _endPress(String actionCode) {
    final start = _pressedAt.remove(actionCode);
    if (start == null) return;
    setState(() {
      _log = _log.add(
        ActionTrackerEvent(actionCode: actionCode, at: start, until: _elapsed),
      );
    });
    _publish();
  }

  void _undo() {
    if (_log.isEmpty) return;
    setState(() => _log = _log.undo());
    _publish();
  }

  void _publish() {
    final values = _log.toFieldValues(widget.field.actions);
    values.forEach(widget.onFieldChanged);
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.field.actions;
    if (actions.isEmpty) {
      return Text(
        'This action tracker has no actions configured.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final duration = widget.field.timerDuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              _formatElapsed(_elapsed),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (duration != null) ...[
              const SizedBox(width: 8),
              Text(
                'of ${ActionTrackerLog.formatSeconds(duration)}s',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: _log.isEmpty ? 'Nothing to undo' : 'Undo last',
              onPressed: _log.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Reset',
              onPressed: _stopwatch == null ? null : _reset,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
            FilledButton.icon(
              onPressed: _autoStopped ? null : (_running ? _stop : _start),
              icon: Icon(
                _running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                _autoStopped ? 'Done' : (_running ? 'Stop' : 'Start'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final action in actions) _actionButton(action)],
        ),
        if (_log.events.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _logSummary(actions),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _actionButton(TrackedAction action) {
    final label = Text(action.label);

    if (!_running) {
      return OutlinedButton(onPressed: null, child: label);
    }
    if (!_isHold) {
      return OutlinedButton(onPressed: () => _tap(action.code), child: label);
    }

    return Listener(
      onPointerDown: (_) => _beginPress(action.code),
      onPointerUp: (_) => _endPress(action.code),
      onPointerCancel: (_) => _endPress(action.code),
      child: OutlinedButton(
        onPressed: () {},
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pressedAt.containsKey(action.code)) ...[
              const Icon(Icons.fiber_manual_record_rounded, size: 12),
              const SizedBox(width: 6),
            ],
            label,
          ],
        ),
      ),
    );
  }

  String _logSummary(List<TrackedAction> actions) {
    final parts = <String>[];
    for (final action in actions) {
      final count = _log.events
          .where((e) => e.actionCode == action.code)
          .length;
      if (count > 0) parts.add('${action.label} x$count');
    }
    return parts.join(' · ');
  }

  static String _formatElapsed(double seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds - minutes * 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${rest.toStringAsFixed(1).padLeft(4, '0')}';
  }
}
