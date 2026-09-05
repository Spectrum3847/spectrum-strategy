import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trait_config.dart';
import '../scouting/models/team_analysis.dart';
import '../state/trait_table_controller.dart';
import '../theme/strategy_palette.dart';

class TraitTableView extends StatelessWidget {
  const TraitTableView({
    required this.controller,
    required this.teamNumbers,
    required this.analyses,
    this.canEdit = true,
    super.key,
  });

  final TraitTableController controller;

  final bool canEdit;

  final List<int> teamNumbers;

  final Map<int, TeamAnalysis> analyses;

  static const double _kGridWidth = 720;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasMatch) {
      return const _Note('Pick a match to fill in its trait table.');
    }
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (teamNumbers.isEmpty) {
      return const _Note(
        'No robots listed for this match yet. The schedule has to load first.',
      );
    }

    final traits = controller.config.traits;
    if (traits.isEmpty) {
      return const _Note('No traits configured.');
    }

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= _kGridWidth
          ? _Grid(
              controller: controller,
              teamNumbers: teamNumbers,
              analyses: analyses,
              traits: traits,
              canEdit: canEdit,
            )
          : _Cards(
              controller: controller,
              teamNumbers: teamNumbers,
              analyses: analyses,
              traits: traits,
              canEdit: canEdit,
            ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.controller,
    required this.teamNumbers,
    required this.analyses,
    required this.traits,
    required this.canEdit,
  });

  final TraitTableController controller;
  final List<int> teamNumbers;
  final Map<int, TeamAnalysis> analyses;
  final List<TraitDefinition> traits;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final border = StrategyPalette.borderOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        border: TableBorder.all(color: border, width: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: {
          0: const FixedColumnWidth(132),
          for (var i = 1; i <= teamNumbers.length; i++)
            i: const FlexColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: StrategyPalette.surfaceStrongOf(context),
            ),
            children: [
              const _HeaderCell(''),
              for (final team in teamNumbers) _HeaderCell('$team'),
            ],
          ),
          for (final trait in traits)
            TableRow(
              children: [
                _TraitLabel(trait: trait),
                for (final team in teamNumbers)
                  _Cell(
                    controller: controller,
                    trait: trait,
                    teamNumber: team,
                    analysis: analyses[team],
                    canEdit: canEdit,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({
    required this.controller,
    required this.teamNumbers,
    required this.analyses,
    required this.traits,
    required this.canEdit,
  });

  final TraitTableController controller;
  final List<int> teamNumbers;
  final Map<int, TeamAnalysis> analyses;
  final List<TraitDefinition> traits;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: teamNumbers.length,
      itemBuilder: (context, index) {
        final team = teamNumbers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StrategyPalette.surfaceOf(context),
            borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$team',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final trait in traits) ...[
                Text(
                  trait.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: StrategyPalette.mutedTextOf(context),
                  ),
                ),
                _Cell(
                  controller: controller,
                  trait: trait,
                  teamNumber: team,
                  analysis: analyses[team],
                  canEdit: canEdit,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _TraitLabel extends StatelessWidget {
  const _TraitLabel({required this.trait});

  final TraitDefinition trait;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trait.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trait.hint.isNotEmpty)
            Text(
              trait.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: StrategyPalette.mutedTextOf(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({
    required this.controller,
    required this.trait,
    required this.teamNumber,
    required this.analysis,
    required this.canEdit,
  });

  final TraitTableController controller;
  final TraitDefinition trait;
  final int teamNumber;
  final TeamAnalysis? analysis;
  final bool canEdit;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.valueFor(widget.teamNumber, widget.trait.key),
  );
  Timer? _debounce;

  static const _debounceFor = Duration(milliseconds: 600);

  @override
  void dispose() {
    _debounce?.cancel();

    _save();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_debounceFor, _save);
  }

  void _save() {
    final value = _text.text;
    if (value ==
        widget.controller.valueFor(widget.teamNumber, widget.trait.key)) {
      return;
    }
    widget.controller.setCell(
      teamNumber: widget.teamNumber,
      traitKey: widget.trait.key,
      value: value,
    );
  }

  void _acceptDraft(String draft) {
    setState(() => _text.text = draft);
    widget.controller.acceptDraft(
      teamNumber: widget.teamNumber,
      traitKey: widget.trait.key,
    );
  }

  void _dismissDraft() {
    widget.controller.dismissDraft(
      teamNumber: widget.teamNumber,
      traitKey: widget.trait.key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final derived = _derivedLabel(widget.trait, widget.analysis);

    final draft = widget.canEdit && _text.text.trim().isEmpty
        ? widget.controller.draftFor(widget.teamNumber, widget.trait.key)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _text,
            maxLines: null,
            textInputAction: TextInputAction.newline,
            readOnly: !widget.canEdit,
            onChanged: _onChanged,
            onSubmitted: (_) => _save(),
            onTapOutside: (_) => _save(),
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,

              hintText: widget.canEdit ? 'Add a note' : null,
            ),
          ),
          if (draft != null)
            _DraftBanner(
              text: draft,
              onAccept: () => _acceptDraft(draft),
              onDismiss: _dismissDraft,
            ),
          if (derived.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                derived,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftBanner extends StatelessWidget {
  const _DraftBanner({
    required this.text,
    required this.onAccept,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: StrategyPalette.surfaceStrongOf(context),
        borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
        border: Border.all(color: StrategyPalette.primary, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.auto_awesome,
              size: 14,
              color: StrategyPalette.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 16),
            tooltip: 'Keep this draft',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onAccept,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Discard this draft',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

String _derivedLabel(TraitDefinition trait, TeamAnalysis? analysis) {
  if (analysis == null || !analysis.hasData) return '';
  switch (trait.source) {
    case TraitSource.none:
      return '';
    case TraitSource.iqmTotalScore:
      return 'scouted ${analysis.iqmTotalScore.toStringAsFixed(1)}';
    case TraitSource.phaseScore:
      final phase = StrategyPhase.values
          .where((p) => p.name == trait.phase)
          .firstOrNull;
      if (phase == null) return '';
      return 'scouted ${analysis.phaseStats(phase).iqmScore.toStringAsFixed(1)}';
    case TraitSource.scoreStdDev:
      return 'spread ${analysis.scoreStdDev.toStringAsFixed(1)}';
    case TraitSource.avgPenalties:
      return 'penalties ${analysis.avgTotalPenalties.toStringAsFixed(1)}';
    case TraitSource.matchCount:
      final n = analysis.matchCount;
      return n == 1 ? 'from 1 match' : 'from $n matches';
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: StrategyPalette.mutedTextOf(context)),
      ),
    ),
  );
}
