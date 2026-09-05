import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/strategy_palette.dart';
import '../../ui/docs_viewer_screen.dart';

class AccuracyMappingSection extends StatefulWidget {
  const AccuracyMappingSection({this.firestore, super.key});

  final FirebaseFirestore? firestore;

  @override
  State<AccuracyMappingSection> createState() => _AccuracyMappingSectionState();
}

class _AccuracyMappingSectionState extends State<AccuracyMappingSection> {
  bool _loading = true;
  bool _saving = false;
  String? _statusMessage;
  bool _statusIsError = false;
  Map<String, dynamic>? _mapping;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final doc = await _db.doc('appConfig/accuracyMapping').get();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _mapping = doc.exists ? doc.data() : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusIsError = true;
        _statusMessage = 'Failed to load mapping: $e';
      });
    }
  }

  Future<void> _viewJson() async {
    final json = const JsonEncoder.withIndent('  ')
        .convert(_mapping ?? <String, dynamic>{});
    final controller = TextEditingController(text: json);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Current accuracy mapping'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: TextField(
            controller: controller,
            maxLines: null,
            readOnly: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _editJson() async {
    final initial = const JsonEncoder.withIndent('  ').convert(
      _mapping ??
          <String, dynamic>{
            'year': DateTime.now().year,
            'perFieldTolerancePct': 50,
            'perFieldAbsoluteMin': 2,
            'minWrongFields': 3,
            'minWrongFraction': 0.5,
            'egregiousAbsMin': 5,
            'egregiousPct': 200,
            'mappings': <Map<String, dynamic>>[],
          },
    );
    final controller = TextEditingController(text: initial);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit accuracy mapping'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: TextField(
            controller: controller,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'JSON mapping config',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (confirmed != true) return;
    await _save(text);
  }

  Future<void> _save(String jsonText) async {
    setState(() {
      _saving = true;
      _statusMessage = null;
    });
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        throw const FormatException('Top-level value must be a JSON object.');
      }
      parsed = Map<String, dynamic>.from(decoded);
      final mappings = parsed['mappings'];
      if (mappings is! List) {
        throw const FormatException('"mappings" must be an array.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusIsError = true;
        _statusMessage = 'Invalid JSON: $e';
      });
      return;
    }
    try {
      await _db.doc('appConfig/accuracyMapping').set(parsed);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusIsError = false;
        _statusMessage =
            'Mapping saved. Takes effect on the next scout entry submission.';
        _mapping = parsed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusIsError = true;
        _statusMessage = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapping = _mapping;
    final mappingsList = (mapping?['mappings'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Scouting Accuracy',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),

            const DocHelpButton(
              docAsset: 'docs/scouting-accuracy-mapping-guide.md',
              tooltip: 'Open the accuracy mapping guide',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Tune which scout fields are compared against Statbotics and how '
          'lenient the comparison is. The Cloud Function reads this on every '
          'relevant scout entry; saves take effect immediately, no redeploy '
          'required.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_statusMessage != null) ...[
          _AccuracyStatusCard(
            message: _statusMessage!,
            isError: _statusIsError,
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        mapping == null
                            ? 'No mapping configured yet.'
                            : 'Active mapping',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (mapping != null) ...[
                        const SizedBox(height: 8),
                        _row('Year', '${mapping['year'] ?? '—'}'),
                        _row('Field count', '${mappingsList.length}'),
                        _row(
                          'Per-field tolerance %',
                          '${mapping['perFieldTolerancePct'] ?? 50}',
                        ),
                        _row(
                          'Per-field absolute min',
                          '${mapping['perFieldAbsoluteMin'] ?? 2}',
                        ),
                        _row(
                          'Trigger: min wrong fields',
                          '${mapping['minWrongFields'] ?? 3}',
                        ),
                        _row(
                          'Trigger: min wrong fraction',
                          '${mapping['minWrongFraction'] ?? 0.5}',
                        ),
                        _row(
                          'Egregious abs min',
                          '${mapping['egregiousAbsMin'] ?? 5}',
                        ),
                        _row(
                          'Egregious deviation %',
                          '${mapping['egregiousPct'] ?? 200}',
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (_saving)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        FilledButton.icon(
                          onPressed: _editJson,
                          icon: const Icon(Icons.edit_rounded),
                          label: Text(
                            mapping == null
                                ? 'Create mapping'
                                : 'Edit mapping JSON',
                          ),
                        ),
                        if (mapping != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _viewJson,
                            icon: const Icon(Icons.code_rounded),
                            label: const Text('View JSON'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reload'),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _AccuracyStatusCard extends StatelessWidget {
  const _AccuracyStatusCard({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isError
        ? colorScheme.errorContainer
        : StrategyPalette.surfaceOf(context);
    final iconColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSurfaceVariant;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: iconColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
