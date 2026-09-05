import 'package:flutter/material.dart';

import '../models/scout_config.dart';
import '../state/pit_scout_config_controller.dart';

class PitQuestionEditor extends StatefulWidget {
  const PitQuestionEditor({required this.controller, super.key});

  final PitScoutConfigController controller;

  @override
  State<PitQuestionEditor> createState() => _PitQuestionEditorState();
}

class _PitQuestionEditorState extends State<PitQuestionEditor> {
  ScoutConfig get _config => widget.controller.config;

  Future<void> _apply(ScoutConfig next) => widget.controller.updateConfig(next);

  String _codeFor(String title) {
    final words = title
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    var base = '';
    for (var i = 0; i < words.length; i++) {
      final w = words[i].toLowerCase();
      base += i == 0 ? w : (w[0].toUpperCase() + w.substring(1));
    }
    if (base.isEmpty) base = 'question';
    final existing = _config.allFields.map((f) => f.code).toSet();
    if (!existing.contains(base)) return base;
    var n = 2;
    while (existing.contains('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  Future<void> _addSection() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _SectionNameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    final sections = List<ScoutConfigSection>.from(_config.sections)
      ..add(ScoutConfigSection(name: name.trim(), fields: const []));
    await _apply(_config.copyWith(sections: sections));
  }

  Future<void> _removeSection(int sectionIdx) async {
    final section = _config.sections[sectionIdx];
    if (section.fields.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Remove every question from "${section.name}" before deleting the section.',
          ),
        ),
      );
      return;
    }
    final confirmed = await _confirm(
      title: 'Delete section?',
      message: 'Delete the empty section "${section.name}"?',
    );
    if (confirmed != true) return;
    final sections = List<ScoutConfigSection>.from(_config.sections)
      ..removeAt(sectionIdx);
    await _apply(_config.copyWith(sections: sections));
  }

  Future<void> _addQuestion(int sectionIdx) async {
    final result = await showDialog<_QuestionDraft>(
      context: context,
      builder: (ctx) => _QuestionDialog(title: 'Add question'),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final field = ScoutConfigField(
      title: result.title.trim(),
      description: result.description.trim(),
      type: result.type,
      required: result.required,
      code: _codeFor(result.title),
    );
    final sections = List<ScoutConfigSection>.from(_config.sections);
    final fields = List<ScoutConfigField>.from(sections[sectionIdx].fields)
      ..add(field);
    sections[sectionIdx] = sections[sectionIdx].copyWith(fields: fields);
    await _apply(_config.copyWith(sections: sections));
  }

  Future<void> _editQuestion(
    int sectionIdx,
    int fieldIdx,
    ScoutConfigField field,
  ) async {
    final result = await showDialog<_QuestionDraft>(
      context: context,
      builder: (ctx) => _QuestionDialog(
        title: 'Edit question',
        initial: field,

        lockType: true,
      ),
    );
    if (result == null) return;
    final updated = field.copyWith(
      title: result.title.trim().isEmpty ? field.title : result.title.trim(),
      description: result.description.trim(),
      choices: result.choices,
      retiredChoiceKeys: result.retiredChoiceKeys,
    );
    final sections = List<ScoutConfigSection>.from(_config.sections);
    final fields = List<ScoutConfigField>.from(sections[sectionIdx].fields);
    fields[fieldIdx] = updated;
    sections[sectionIdx] = sections[sectionIdx].copyWith(fields: fields);
    await _apply(_config.copyWith(sections: sections));
  }

  Future<void> _removeQuestion(
    int sectionIdx,
    int fieldIdx,
    ScoutConfigField field,
  ) async {
    final confirmed = await _confirm(
      title: 'Delete question?',
      message:
          'Delete "${field.title}"? Answers already submitted keep the value, '
          'but it drops out of new submissions and the Database tab.',
    );
    if (confirmed != true) return;
    final sections = List<ScoutConfigSection>.from(_config.sections);
    final fields = List<ScoutConfigField>.from(sections[sectionIdx].fields)
      ..removeAt(fieldIdx);
    sections[sectionIdx] = sections[sectionIdx].copyWith(fields: fields);
    await _apply(_config.copyWith(sections: sections));
  }

  Future<void> _moveQuestion(int sectionIdx, int fieldIdx, int delta) async {
    final section = _config.sections[sectionIdx];
    final target = fieldIdx + delta;
    if (target < 0 || target >= section.fields.length) return;
    final fields = List<ScoutConfigField>.from(section.fields);
    final field = fields.removeAt(fieldIdx);
    fields.insert(target, field);
    final sections = List<ScoutConfigSection>.from(_config.sections);
    sections[sectionIdx] = section.copyWith(fields: fields);
    await _apply(_config.copyWith(sections: sections));
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var si = 0; si < _config.sections.length; si++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _SectionCard(
                  section: _config.sections[si],
                  onAddQuestion: () => _addQuestion(si),
                  onDeleteSection: () => _removeSection(si),
                  onEditQuestion: (fi, field) => _editQuestion(si, fi, field),
                  onDeleteQuestion: (fi, field) =>
                      _removeQuestion(si, fi, field),
                  onMoveQuestion: (fi, delta) => _moveQuestion(si, fi, delta),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addSection,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add section'),
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onAddQuestion,
    required this.onDeleteSection,
    required this.onEditQuestion,
    required this.onDeleteQuestion,
    required this.onMoveQuestion,
  });

  final ScoutConfigSection section;
  final VoidCallback onAddQuestion;
  final VoidCallback onDeleteSection;
  final void Function(int fieldIdx, ScoutConfigField field) onEditQuestion;
  final void Function(int fieldIdx, ScoutConfigField field) onDeleteQuestion;
  final void Function(int fieldIdx, int delta) onMoveQuestion;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    section.name.isEmpty ? 'Untitled section' : section.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete section',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: onDeleteSection,
                ),
              ],
            ),
            for (var fi = 0; fi < section.fields.length; fi++)
              _QuestionTile(
                field: section.fields[fi],
                canMoveUp: fi > 0,
                canMoveDown: fi < section.fields.length - 1,
                onEdit: () => onEditQuestion(fi, section.fields[fi]),
                onDelete: () => onDeleteQuestion(fi, section.fields[fi]),
                onMoveUp: () => onMoveQuestion(fi, -1),
                onMoveDown: () => onMoveQuestion(fi, 1),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddQuestion,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add question'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.field,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ScoutConfigField field;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: canMoveUp ? onMoveUp : null,
              ),
              IconButton(
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: canMoveDown ? onMoveDown : null,
              ),
            ],
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.title,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${field.type.displayName}${field.required ? ' - required' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit question',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Delete question',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _SectionNameDialog extends StatefulWidget {
  const _SectionNameDialog();

  @override
  State<_SectionNameDialog> createState() => _SectionNameDialogState();
}

class _SectionNameDialogState extends State<_SectionNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New section'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Section name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _QuestionDraft {
  _QuestionDraft({
    required this.title,
    required this.description,
    required this.type,
    required this.required,
    this.choices,
    this.retiredChoiceKeys,
  });

  final String title;
  final String description;
  final ScoutFieldType type;
  final bool required;

  final Map<String, String>? choices;

  final Set<String>? retiredChoiceKeys;
}

const List<ScoutFieldType> _editableQuestionTypes = [
  ScoutFieldType.text,
  ScoutFieldType.number,
  ScoutFieldType.boolean,
];

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({
    required this.title,
    this.initial,
    this.lockType = false,
  });

  final String title;
  final ScoutConfigField? initial;
  final bool lockType;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late ScoutFieldType _type = widget.initial?.type ?? ScoutFieldType.text;
  late bool _required = widget.initial?.required ?? false;
  late final List<_ChoiceDraft> _choices = [
    for (final e
        in widget.initial?.choices?.entries ??
            const <MapEntry<String, String>>[])
      if (!(widget.initial?.retiredChoiceKeys.contains(e.key) ?? false))
        _ChoiceDraft(key: e.key, label: e.value),
  ];

  late final Map<String, String> _retiredChoices = {
    for (final key in widget.initial?.retiredChoiceKeys ?? const <String>{})
      key: widget.initial?.choices?[key] ?? key,
  };

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _addChoice() async {
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          const _ChoiceLabelDialog(title: 'Add choice', confirmText: 'Add'),
    );
    if (label == null || label.trim().isEmpty) return;
    setState(() {
      _choices.add(
        _ChoiceDraft(
          key: _choiceKeyFor(label.trim(), _choices.map((c) => c.key)),
          label: label.trim(),
        ),
      );
    });
  }

  Future<void> _renameChoice(int index) async {
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => _ChoiceLabelDialog(
        title: 'Rename choice',
        confirmText: 'Rename',
        initialLabel: _choices[index].label,
      ),
    );
    if (label == null || label.trim().isEmpty) return;
    setState(() => _choices[index].label = label.trim());
  }

  void _removeChoice(int index) {
    if (_choices.length <= 1) return;

    setState(() {
      final removed = _choices.removeAt(index);
      _retiredChoices[removed.key] = removed.label;
    });
  }

  void _moveChoice(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _choices.length) return;
    setState(() {
      final choice = _choices.removeAt(index);
      _choices.insert(target, choice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final typeOptions = {..._editableQuestionTypes, _type}.toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Question',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Hint text (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ScoutFieldType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in typeOptions)
                  DropdownMenuItem(value: t, child: Text(t.displayName)),
              ],
              onChanged: widget.lockType
                  ? null
                  : (t) => setState(() => _type = t ?? _type),
            ),
            if (_type == ScoutFieldType.select) ...[
              const SizedBox(height: 12),
              _ChoicesEditor(
                choices: _choices,
                onAdd: _addChoice,
                onRename: _renameChoice,
                onRemove: _removeChoice,
                onMove: _moveChoice,
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Required'),
              value: _required,
              onChanged: (v) => setState(() => _required = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _QuestionDraft(
              title: _titleCtrl.text,
              description: _descCtrl.text,
              type: _type,
              required: _required,

              choices: _type == ScoutFieldType.select
                  ? {
                      for (final c in _choices) c.key: c.label,
                      ..._retiredChoices,
                    }
                  : null,
              retiredChoiceKeys: _type == ScoutFieldType.select
                  ? _retiredChoices.keys.toSet()
                  : null,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ChoiceDraft {
  _ChoiceDraft({required this.key, required this.label});

  final String key;
  String label;
}

String _choiceKeyFor(String label, Iterable<String> existingKeys) {
  final words = label
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var base = '';
  for (var i = 0; i < words.length; i++) {
    final w = words[i].toLowerCase();
    base += i == 0 ? w : (w[0].toUpperCase() + w.substring(1));
  }
  if (base.isEmpty) base = 'choice';
  final existing = existingKeys.toSet();
  if (!existing.contains(base)) return base;
  var n = 2;
  while (existing.contains('$base$n')) {
    n++;
  }
  return '$base$n';
}

class _ChoicesEditor extends StatelessWidget {
  const _ChoicesEditor({
    required this.choices,
    required this.onAdd,
    required this.onRename,
    required this.onRemove,
    required this.onMove,
  });

  final List<_ChoiceDraft> choices;
  final VoidCallback onAdd;
  final void Function(int index) onRename;
  final void Function(int index) onRemove;
  final void Function(int index, int delta) onMove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choices', style: Theme.of(context).textTheme.titleSmall),
            if (choices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No choices yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (var i = 0; i < choices.length; i++)
              _ChoiceTile(
                label: choices[i].label,
                canMoveUp: i > 0,
                canMoveDown: i < choices.length - 1,

                canRemove: choices.length > 1,
                onRename: () => onRename(i),
                onRemove: () => onRemove(i),
                onMoveUp: () => onMove(i, -1),
                onMoveDown: () => onMove(i, 1),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add choice'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canRemove,
    required this.onRename,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final String label;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canRemove;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Move choice up',
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: canMoveUp ? onMoveUp : null,
              ),
              IconButton(
                tooltip: 'Move choice down',
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: canMoveDown ? onMoveDown : null,
              ),
            ],
          ),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          IconButton(
            tooltip: 'Rename choice',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onRename,
          ),
          IconButton(
            tooltip: 'Remove choice',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: canRemove ? onRemove : null,
          ),
        ],
      ),
    );
  }
}

class _ChoiceLabelDialog extends StatefulWidget {
  const _ChoiceLabelDialog({
    required this.title,
    required this.confirmText,
    this.initialLabel = '',
  });

  final String title;
  final String confirmText;
  final String initialLabel;

  @override
  State<_ChoiceLabelDialog> createState() => _ChoiceLabelDialogState();
}

class _ChoiceLabelDialogState extends State<_ChoiceLabelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLabel,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Choice label',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
