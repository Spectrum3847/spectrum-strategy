import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/strategy_palette.dart';
import '../../ui/docs_viewer_screen.dart';

class SheetsExportSection extends StatefulWidget {
  const SheetsExportSection({this.firestore, super.key});

  final FirebaseFirestore? firestore;

  @override
  State<SheetsExportSection> createState() => _SheetsExportSectionState();
}

class _SheetsExportSectionState extends State<SheetsExportSection> {
  bool _loading = true;
  bool _saving = false;
  String? _statusMessage;
  bool _statusIsError = false;
  Map<String, dynamic>? _config;
  bool _enabled = false;
  final TextEditingController _idController = TextEditingController();

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final doc = await _db.doc('appConfig/sheetsExport').get();
      if (!mounted) return;
      final data = doc.exists ? doc.data() : null;
      setState(() {
        _loading = false;
        _config = data;
        _enabled = data?['enabled'] == true;
        _idController.text = (data?['spreadsheetId'] as String?) ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusIsError = true;
        _statusMessage = 'Failed to load Sheets export config: $e';
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _statusMessage = null;
    });
    try {
      await _db.doc('appConfig/sheetsExport').set(<String, dynamic>{
        'spreadsheetId': _idController.text.trim(),
        'enabled': _enabled,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusIsError = false;
        _statusMessage = _enabled
            ? 'Saved. The next export runs within 15 minutes.'
            : 'Saved. Exports are off.';
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
    final email = _config?['serviceAccountEmail'] as String?;
    final lastExportAt = _config?['lastExportAt'] as String?;
    final lastError = _config?['lastError'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Sheets export',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const DocHelpButton(
              docAsset: 'docs/sheets-export-setup.md',
              tooltip: 'Open the Sheets export setup guide',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Mirror the scouting database into a Google Sheet every 15 '
          'minutes, one tab for match scouting and one for pit scouting. '
          'Share the spreadsheet with the service account as an editor, '
          'then paste its id here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_statusMessage != null) ...[
          _SheetsStatusCard(message: _statusMessage!, isError: _statusIsError),
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
                      if (email != null && email.isNotEmpty)
                        _copyRow('Share the sheet with', email)
                      else
                        Text(
                          'The service account email appears here after the '
                          'export job runs for the first time.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (lastExportAt != null)
                        _row('Last export', lastExportAt),
                      if (lastError != null && lastError.isNotEmpty)
                        _row('Last error', lastError),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          labelText: 'Spreadsheet id',
                          helperText:
                              'From the sheet URL: docs.google.com/'
                              'spreadsheets/d/<id>/edit',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Export enabled'),
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      if (_saving)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Save'),
                        ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Row(
      children: [
        Expanded(child: _row(label, value)),
        IconButton(
          tooltip: 'Copy email',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!mounted) return;
            setState(() {
              _statusIsError = false;
              _statusMessage = 'Service account email copied.';
            });
          },
        ),
      ],
    );
  }
}

class _SheetsStatusCard extends StatelessWidget {
  const _SheetsStatusCard({required this.message, required this.isError});

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
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: iconColor,
              size: 20,
            ),
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
