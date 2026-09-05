import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/strategy_stroke.dart';
import '../models/trex_trait.dart';
import '../models/trex_trait_report.dart';
import '../scouting/state/scout_drawing_controller.dart';
import '../scouting/widgets/scout_drawing_canvas.dart';
import '../state/failed_write_tracker.dart';
import '../state/trex_trait_report_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/empty_state.dart';
import '../widgets/sync_status_pill.dart';

class TrexTraitsScreen extends StatelessWidget {
  const TrexTraitsScreen({required this.controller, super.key});

  final TrexTraitReportController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: TrexTrait.values.length,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: true,
              tabs: [
                for (final trait in TrexTrait.values) Tab(text: trait.label),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final trait in TrexTrait.values)
                  _TrexTraitTabView(controller: controller, trait: trait),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrexTraitTabView extends StatefulWidget {
  const _TrexTraitTabView({required this.controller, required this.trait});

  final TrexTraitReportController controller;
  final TrexTrait trait;

  @override
  State<_TrexTraitTabView> createState() => _TrexTraitTabViewState();
}

class _TrexTraitTabViewState extends State<_TrexTraitTabView> {
  final TextEditingController _teamCtrl = TextEditingController();
  final TextEditingController _matchCtrl = TextEditingController();
  final TextEditingController _eventCtrl = TextEditingController();
  final TextEditingController _reportCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScoutDrawingController _drawingController = ScoutDrawingController();

  bool _drawingOpen = false;
  bool _submitting = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _teamCtrl.dispose();
    _matchCtrl.dispose();
    _eventCtrl.dispose();
    _reportCtrl.dispose();
    _searchCtrl.dispose();
    _drawingController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final team = int.tryParse(_teamCtrl.text.trim());
    final match = int.tryParse(_matchCtrl.text.trim());
    if (team == null || team <= 0) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Enter a team number.';
      });
      return;
    }
    if (match == null || match < 0) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Enter a match number.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _statusMessage = null;
    });
    final report = TrexTraitReport(
      trait: widget.trait.key,
      teamNumber: team,
      matchNumber: match,
      eventName: _eventCtrl.text.trim(),
      report: _reportCtrl.text.trim(),

      strokes:
          _drawingController.toJson()[_drawingController.selectedPhase.name]
              as List<dynamic>?,
      updatedAt: DateTime.now().toUtc(),
    );
    final saved = await widget.controller.submitReport(report);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _statusIsError = !saved;
      _statusMessage = saved
          ? 'Report submitted for team $team.'
          : (widget.controller.lastError ?? 'Could not save the report.');
    });
    if (saved) {
      _teamCtrl.clear();
      _matchCtrl.clear();
      _eventCtrl.clear();
      _reportCtrl.clear();
      _drawingController.clear();
      setState(() => _drawingOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.controller.failedWrites.hasFailures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _TrexSyncPill(
                        failedWrites: widget.controller.failedWrites,
                      ),
                    ),
                  ),
                _InstructionsBox(trait: widget.trait),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    labelText: 'Search team number',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                _ReportForm(
                  teamCtrl: _teamCtrl,
                  matchCtrl: _matchCtrl,
                  eventCtrl: _eventCtrl,
                  reportCtrl: _reportCtrl,
                  drawingController: _drawingController,
                  drawingOpen: _drawingOpen,
                  onToggleDrawing: () =>
                      setState(() => _drawingOpen = !_drawingOpen),
                  submitting: _submitting,
                  statusMessage: _statusMessage,
                  statusIsError: _statusIsError,
                  onSubmit: _submit,
                ),
                const SizedBox(height: 24),
                Text(
                  'T-Rex database',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _TrexReportDatabase(
                  reports: widget.controller.reports,
                  search: _searchCtrl.text.trim(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InstructionsBox extends StatelessWidget {
  const _InstructionsBox({required this.trait});

  final TrexTrait trait;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceOf(context),
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${trait.label} T-Rex lookout',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            trait.instructions,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReportForm extends StatelessWidget {
  const _ReportForm({
    required this.teamCtrl,
    required this.matchCtrl,
    required this.eventCtrl,
    required this.reportCtrl,
    required this.drawingController,
    required this.drawingOpen,
    required this.onToggleDrawing,
    required this.submitting,
    required this.statusMessage,
    required this.statusIsError,
    required this.onSubmit,
  });

  final TextEditingController teamCtrl;
  final TextEditingController matchCtrl;
  final TextEditingController eventCtrl;
  final TextEditingController reportCtrl;
  final ScoutDrawingController drawingController;
  final bool drawingOpen;
  final VoidCallback onToggleDrawing;
  final bool submitting;
  final String? statusMessage;
  final bool statusIsError;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New report', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          TextField(
            controller: teamCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Team number',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: matchCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Match number',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: eventCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Event name',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reportCtrl,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              labelText: 'Report',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onToggleDrawing,
              icon: Icon(
                drawingOpen ? Icons.expand_less_rounded : Icons.draw_outlined,
              ),
              label: Text(drawingOpen ? 'Hide drawing' : 'Add drawing'),
            ),
          ),
          if (drawingOpen) ...[
            const SizedBox(height: 8),
            _DrawingCapture(controller: drawingController),
          ],
          const SizedBox(height: 16),
          if (statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                statusMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusIsError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          FilledButton(
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

class _DrawingCapture extends StatelessWidget {
  const _DrawingCapture({required this.controller});

  final ScoutDrawingController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tool = controller.selectedTool;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ToolButton(
                  icon: Icons.draw_rounded,
                  label: 'Draw',
                  selected: tool == StrategyTool.draw,
                  onTap: () => controller.selectedTool = StrategyTool.draw,
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.backspace_rounded,
                  label: 'Erase',
                  selected: tool == StrategyTool.delete,
                  onTap: () => controller.selectedTool = StrategyTool.delete,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.isEmpty ? null : controller.clear,
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
              child: ScoutDrawingCanvas(controller: controller),
            ),
          ],
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? StrategyPalette.chipSelectedOf(context)
        : StrategyPalette.chipUnselectedOf(context);
    final foreground = selected
        ? StrategyPalette.onChipSelectedOf(context)
        : StrategyPalette.onChipUnselectedOf(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: foreground, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrexReportDatabase extends StatelessWidget {
  const _TrexReportDatabase({required this.reports, required this.search});

  final List<TrexTraitReport> reports;
  final String search;

  @override
  Widget build(BuildContext context) {
    final byTeam = <int, List<TrexTraitReport>>{};
    for (final report in reports) {
      (byTeam[report.teamNumber] ??= <TrexTraitReport>[]).add(report);
    }
    var teams = byTeam.keys.toList()..sort();
    if (search.isNotEmpty) {
      teams = teams.where((t) => t.toString().contains(search)).toList();
    }
    if (teams.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        message: reports.isEmpty
            ? 'No T-Rex reports yet. Submit one above.'
            : 'No team matches "$search".',
      );
    }
    return Column(
      children: [
        for (final team in teams)
          _TeamGroup(team: team, reports: byTeam[team]!),
      ],
    );
  }
}

class _TeamGroup extends StatelessWidget {
  const _TeamGroup({required this.team, required this.reports});

  final int team;
  final List<TrexTraitReport> reports;

  @override
  Widget build(BuildContext context) {
    final byTrait = <TrexTrait, List<TrexTraitReport>>{};
    for (final report in reports) {
      final trait = TrexTrait.byKey(report.trait);
      if (trait == null) continue;
      (byTrait[trait] ??= <TrexTraitReport>[]).add(report);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Team $team',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${reports.length} '
            '${reports.length == 1 ? 'report' : 'reports'}',
          ),
          children: [
            for (final trait in TrexTrait.values)
              if (byTrait[trait] case final entries? when entries.isNotEmpty)
                _TraitGroup(trait: trait, reports: entries),
          ],
        ),
      ),
    );
  }
}

class _TraitGroup extends StatelessWidget {
  const _TraitGroup({required this.trait, required this.reports});

  final TrexTrait trait;
  final List<TrexTraitReport> reports;

  @override
  Widget build(BuildContext context) {
    final sorted = reports.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trait.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final report in sorted) _ReportCard(report: report),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final TrexTraitReport report;

  @override
  Widget build(BuildContext context) {
    final strokes = _strokesFrom(report.strokes);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: StrategyPalette.borderOf(context)),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Match ${report.matchNumber}'
            '${report.eventName.isEmpty ? '' : ' · ${report.eventName}'}',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (report.report.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(report.report, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (strokes.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: FieldStrokePreview(strokes: strokes),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            report.authorDisplayName.isEmpty
                ? 'Unknown scouter'
                : report.authorDisplayName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static List<StrategyStroke> _strokesFrom(List<dynamic> raw) {
    final strokes = <StrategyStroke>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        strokes.add(StrategyStroke.fromJson(entry.cast<String, dynamic>()));
      } catch (_) {}
    }
    return strokes;
  }
}

class _TrexSyncPill extends StatelessWidget {
  const _TrexSyncPill({required this.failedWrites});

  final FailedWriteTracker failedWrites;

  @override
  Widget build(BuildContext context) {
    final count = failedWrites.unlandedCount;
    return SyncStatusPill(
      label: '$count report${count == 1 ? '' : 's'} not saved',
      icon: Icons.cloud_off_rounded,
      isFailure: true,
    );
  }
}
