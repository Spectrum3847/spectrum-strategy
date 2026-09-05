import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'action_tracker_field.dart';

import '../models/scout_config.dart';
import '../models/scout_schedule.dart';

const double _kLabelSize = 15;
const double _kValueSize = 16;
const double _kCounterValueSize = 24;

TextStyle? _valueStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge
        ?.copyWith(fontSize: _kValueSize, fontWeight: FontWeight.w600);

TextStyle? _stepStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontSize: _kLabelSize, fontWeight: FontWeight.w700);

class ScoutFormSection extends StatelessWidget {
  const ScoutFormSection({
    required this.section,
    required this.keyPrefix,
    required this.values,
    required this.textControllers,
    required this.onFieldChanged,
    this.actionTrackerResetTokens = const <String, int>{},
    this.schedule = const ScoutSchedule.empty(),
    super.key,
  });

  final ScoutSchedule schedule;

  final Map<String, int> actionTrackerResetTokens;

  final ScoutConfigSection section;

  final String keyPrefix;

  final Map<String, dynamic> values;

  final Map<String, TextEditingController> textControllers;
  final void Function(String code, dynamic value) onFieldChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            section.name,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: section.fields
                  .map(
                    (field) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildField(context, field),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildField(BuildContext context, ScoutConfigField field) {
    final value = values[field.code] ?? field.effectiveDefault;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                field.title + (field.required ? ' *' : ''),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: _kLabelSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (field.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(field.description, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        _buildFieldInput(context, field, value),
      ],
    );
  }

  Widget _buildFieldInput(
    BuildContext context,
    ScoutConfigField field,
    dynamic value,
  ) {
    switch (field.type) {
      case ScoutFieldType.text:
        return TextField(
          key: ValueKey<String>('$keyPrefix-${field.code}'),
          controller: textControllers[field.code],
          style: _valueStyle(context),
          decoration: InputDecoration(
            hintText: field.title,
            border: const OutlineInputBorder(),
          ),
        );

      case ScoutFieldType.number:
        return TextField(
          key: ValueKey<String>('$keyPrefix-${field.code}'),
          controller: textControllers[field.code],
          keyboardType: const TextInputType.numberWithOptions(decimal: false),

          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: _valueStyle(context),
          decoration: InputDecoration(
            hintText: field.min != null && field.max != null
                ? '${field.min!.toInt()} - ${field.max!.toInt()}'
                : null,
            border: const OutlineInputBorder(),
          ),
        );

      case ScoutFieldType.boolean:
        return Row(
          children: [
            Switch(
              value: value is bool ? value : false,
              onChanged: (v) => onFieldChanged(field.code, v),
            ),
            Text(
              value is bool && value ? 'Yes' : 'No',
              style: _valueStyle(context),
            ),
          ],
        );

      case ScoutFieldType.select:
        final choices = field.choices;
        if (choices == null || choices.isEmpty) {
          return const Text('No choices configured.');
        }
        final currentValue = value?.toString() ?? '';

        final validValue =
            field.resolveStoredChoice(currentValue) ??
            field.activeChoices.keys.firstOrNull ??
            '';

        if (validValue != currentValue && validValue.isNotEmpty) {
          values[field.code] = validValue;
        }

        final options = field.choiceOptions(
          validValue.isEmpty ? const <String>[] : <String>[validValue],
        );
        return DropdownButtonFormField<String>(
          key: ValueKey<String>('$keyPrefix-${field.code}'),
          initialValue: validValue.isEmpty ? null : validValue,
          style: _valueStyle(context),

          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (v) {
            if (v != null) onFieldChanged(field.code, v);
          },

          items: <DropdownMenuItem<String>>[
            for (final e in options.entries)
              DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
          ],
        );

      case ScoutFieldType.range:
        final min = field.min ?? 0;
        final max = field.max ?? 100;
        final step = field.step ?? 1;
        final doubleValue = (value is num)
            ? value.toDouble().clamp(min, max)
            : min;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Slider(
              value: doubleValue,
              min: min,
              max: max,
              divisions: step > 0 ? ((max - min) / step).round() : null,
              label: doubleValue.toStringAsFixed(step < 1 ? 1 : 0),
              onChanged: (v) => onFieldChanged(field.code, v),
            ),
            Text(
              '${doubleValue.toStringAsFixed(step < 1 ? 1 : 0)} / ${max.toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: _valueStyle(context),
            ),
          ],
        );

      case ScoutFieldType.counter:
      case ScoutFieldType.multiCounter:
        final intValue = (value is num) ? value.toInt() : 0;
        return _CounterField(
          value: intValue,
          min: field.min?.toInt(),
          max: field.max?.toInt(),
          buttons: field.buttons,
          onChanged: (v) => onFieldChanged(field.code, v),
        );

      case ScoutFieldType.tbaMatchNumber:
        final matchNumbers = schedule.matchNumbers;
        if (matchNumbers.isEmpty) {
          return TextField(
            key: ValueKey<String>('$keyPrefix-${field.code}'),
            controller: textControllers[field.code],
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: _valueStyle(context),
            decoration: const InputDecoration(
              hintText: 'Match number',
              border: OutlineInputBorder(),
            ),
          );
        }
        final currentMatch = (value is num)
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '');
        return DropdownButtonFormField<int>(
          key: ValueKey<String>('$keyPrefix-${field.code}'),
          initialValue: matchNumbers.contains(currentMatch)
              ? currentMatch
              : null,
          isExpanded: true,
          style: _valueStyle(context),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('Select a match'),
          items: <DropdownMenuItem<int>>[
            for (final number in matchNumbers)
              DropdownMenuItem<int>(
                value: number,
                child: Text('Match $number'),
              ),
          ],
          onChanged: (v) {
            if (v != null) onFieldChanged(field.code, v);
          },
        );

      case ScoutFieldType.tbaTeamAndRobot:
        final selectedMatch = int.tryParse(
          values['matchNumber']?.toString() ?? '',
        );
        final robots = schedule.robotsFor(selectedMatch);
        final selected = value is Map
            ? value['robotPosition']?.toString()
            : null;
        if (robots.isEmpty) {
          final team = value is Map ? value['teamNumber'] : null;
          return TextFormField(
            key: ValueKey<String>('$keyPrefix-${field.code}'),
            initialValue: team?.toString() ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: _valueStyle(context),
            decoration: const InputDecoration(
              hintText: 'Team number',
              border: OutlineInputBorder(),
            ),
            onChanged: (text) {
              final parsed = int.tryParse(text.trim());
              onFieldChanged(
                field.code,
                parsed == null
                    ? null
                    : <String, dynamic>{
                        'teamNumber': parsed,

                        'robotPosition': '',
                      },
              );
            },
          );
        }
        return DropdownButtonFormField<String>(
          key: ValueKey<String>('$keyPrefix-${field.code}'),
          initialValue: robots.any((r) => r.position == selected)
              ? selected
              : null,
          isExpanded: true,
          style: _valueStyle(context),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('Select a team'),
          items: <DropdownMenuItem<String>>[
            for (final robot in robots)
              DropdownMenuItem<String>(
                value: robot.position,
                child: Text(robot.label),
              ),
          ],
          onChanged: (position) {
            final robot = robots.firstWhere((r) => r.position == position);
            onFieldChanged(field.code, <String, dynamic>{
              'teamNumber': robot.team,
              'robotPosition': robot.position,
            });
          },
        );

      case ScoutFieldType.actionTracker:
        return ActionTrackerField(
          key: ValueKey<String>('$keyPrefix-${field.code}'),
          field: field,

          onFieldChanged: onFieldChanged,
          resetToken: actionTrackerResetTokens[field.code] ?? 0,
        );

      case ScoutFieldType.checkboxSelect:
        final choices = field.choices;
        if (choices == null || choices.isEmpty) {
          return const Text('No choices configured.');
        }
        final selected = ScoutConfigField.selectedKeys(value);
        return _CheckboxSelectField(
          key: ValueKey<String>('$keyPrefix-${field.code}'),

          choices: field.choiceOptions(selected),
          selected: selected,
          onChanged: (keys) =>
              onFieldChanged(field.code, ScoutConfigField.joinKeys(keys)),
        );
    }
  }
}

class _CheckboxSelectField extends StatelessWidget {
  const _CheckboxSelectField({
    required this.choices,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Map<String, String> choices;

  final List<String> selected;

  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in choices.entries)
          FilterChip(
            label: Text(entry.value, style: _valueStyle(context)),
            selected: selected.contains(entry.key),
            onSelected: (on) {
              final next = <String>[
                for (final key in choices.keys)
                  if (key == entry.key ? on : selected.contains(key)) key,
              ];
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _CounterField extends StatelessWidget {
  const _CounterField({
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.buttons,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int? min;
  final int? max;
  final List<int>? buttons;

  @override
  Widget build(BuildContext context) {
    final steps = (buttons == null || buttons!.isEmpty)
        ? const <int>[1]
        : buttons!;
    final effectiveMin = min ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  onPressed: value - steps[i] < effectiveMin
                      ? null
                      : () => onChanged(value - steps[i]),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    textStyle: _stepStyle(context),
                  ),
                  child: Text('-${steps[i]}'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value.toString(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: _kCounterValueSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  onPressed: max != null && value + steps[i] > max!
                      ? null
                      : () => onChanged(value + steps[i]),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    textStyle: _stepStyle(context),
                  ),
                  child: Text('+${steps[i]}'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
