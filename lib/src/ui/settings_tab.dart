import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../services/debug_info.dart';
import '../services/desktop_launcher_service.dart';
import '../services/desktop_self_update_service.dart';
import '../services/desktop_update_service.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/scout_config_controller.dart';
import '../scouting/ui/accuracy_mapping_section.dart';
import '../scouting/ui/pit_question_editor.dart';
import '../scouting/ui/sheets_export_section.dart';
import '../services/issue_report_service.dart';
import '../services/spectrum_auth_service.dart';
import '../services/telemetry_service.dart';
import '../services/web_channel_service.dart';
import '../models/user_role.dart';
import 'assistant_setup_card.dart';
import 'docs_viewer_screen.dart';
import '../state/event_controller.dart';
import '../state/theme_controller.dart';
import '../state/user_role_controller.dart';
import '../theme/strategy_palette.dart';
import '../widgets/segment_label.dart';
import 'event_picker_dialog.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    required this.configController,
    required this.themeController,
    required this.eventController,
    required this.userRoleController,
    required this.pitScoutConfigController,
    required this.authService,
    this.issueReportService,
    this.telemetryService,
    this.onReplayTour,
    super.key,
  });

  final ScoutConfigController configController;
  final ThemeController themeController;
  final EventController eventController;
  final UserRoleController userRoleController;
  final PitScoutConfigController pitScoutConfigController;
  final SpectrumAuthService authService;

  final IssueReportService? issueReportService;

  final TelemetryService? telemetryService;

  final VoidCallback? onReplayTour;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _loading = false;
  String? _statusMessage;
  bool _statusIsError = false;

  bool _pitLoading = false;
  String? _pitStatusMessage;
  bool _pitStatusIsError = false;

  late final IssueReportService _reportService =
      widget.issueReportService ?? IssueReportService();

  ScoutConfigController get _ctrl => widget.configController;
  ThemeController get _themeCtrl => widget.themeController;
  EventController get _eventCtrl => widget.eventController;
  UserRoleController get _roleCtrl => widget.userRoleController;
  PitScoutConfigController get _pitCtrl => widget.pitScoutConfigController;
  ScoutConfig get _config => _ctrl.config;
  ScoutConfig get _pitConfig => _pitCtrl.config;
  bool get _canEdit => _roleCtrl.roles.canEditScoutConfig;
  bool get _canEditAccuracyMapping => _roleCtrl.roles.canEditAccuracyMapping;
  bool get _isAdmin => _roleCtrl.roles.canManageUsers;

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  String _rolesLabel() {
    final roles = _roleCtrl.roles.map((r) => r.displayName).toList()..sort();
    return roles.join(', ');
  }

  Future<void> _openEventPicker() async {
    await showEventPicker(context, _eventCtrl);
  }

  bool get _canReport =>
      widget.authService.currentUser != null && _roleCtrl.roles.isMember;

  static const List<String> _reportAreas = [
    'Strategy board',
    'Scouting capture / QR',
    'Firebase sync',
    'Prematch (event team list, EPA/rank)',
    'Team compare',
    'Playoff ranking',
    'Film review',
    'Pick lists',
    'Auth / sign-in',
    'Build, CI, or release tooling',
    'Docs',
    'Not sure',
  ];

  static const List<String> _reportImpacts = [
    'Blocks work completely',
    'Major degradation or frequent failure',
    'Minor bug or occasional failure',
    'Cosmetic issue',
  ];

  Future<void> _reportProblem() async {
    final user = widget.authService.currentUser;
    if (user == null) return;

    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    var kind = 'bug';
    String? area;
    String? impact;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Report a problem'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your name and device details are attached automatically '
                    'to help us debug.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'bug', label: SegmentLabel('Bug')),
                      ButtonSegment(
                        value: 'feedback',
                        label: SegmentLabel('Feedback'),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (selection) =>
                        setDialogState(() => kind = selection.first),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: area,
                    decoration: const InputDecoration(
                      labelText: 'Area',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final option in _reportAreas)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) => setDialogState(() => area = value),
                  ),
                  if (kind == 'bug') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: impact,
                      decoration: const InputDecoration(
                        labelText: 'Impact',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final option in _reportImpacts)
                          DropdownMenuItem(value: option, child: Text(option)),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => impact = value),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Summary',
                      hintText: 'Board did not save my drawing',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 5,
                    maxLength: 4096,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: kind == 'feedback'
                          ? 'Your feedback'
                          : 'What happened',
                      hintText: kind == 'feedback'
                          ? 'What would you like to see?'
                          : 'Steps to reproduce, what you expected, etc.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
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
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    titleCtrl.dispose();
    bodyCtrl.dispose();
    if (submitted != true) return;
    if (title.isEmpty) {
      _showReportSnack('Add a short summary before sending.', isError: true);
      return;
    }
    try {
      await _reportService.submit(
        title: title,
        body: body,
        reporterUid: user.uid,
        reporterName: user.displayName.isNotEmpty
            ? user.displayName
            : 'Unknown',
        roles: _rolesLabel(),
        kind: kind,
        area: area ?? '',
        impact: kind == 'bug' ? (impact ?? '') : '',
      );
      _showReportSnack('Report sent. Thank you.');
    } catch (e) {
      _showReportSnack('Could not send the report: $e', isError: true);
    }
  }

  void _showReportSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _uploadJson() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted) return;
      if (result.isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }
      final file = result.first;
      final bytes = await file.readAsBytes();
      final jsonString = utf8.decode(bytes);
      await _ctrl.loadFromJsonString(jsonString);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusIsError = false;
        _statusMessage =
            'Config loaded: "${_config.title}" with '
            '${_config.allFields.length} fields across '
            '${_config.sections.length} sections.'
            '${_unsupportedTypeWarning(_config)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusIsError = true;
        _statusMessage = 'Failed to load config: $e';
      });
    }
  }

  Future<void> _pasteJson() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste JSON config'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Paste QRScout-compatible JSON here...',
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
            child: const Text('Load'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      await _ctrl.loadFromJsonString(text);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusIsError = false;
        _statusMessage =
            'Config loaded: "${_config.title}" with '
            '${_config.allFields.length} fields.'
            '${_unsupportedTypeWarning(_config)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusIsError = true;
        _statusMessage = 'Failed to load config: $e';
      });
    }
  }

  String _unsupportedTypeWarning(ScoutConfig config) {
    final split = config.unsupportedTypesSplit;
    if (split.known.isEmpty && split.unrecognised.isEmpty) return '';

    final parts = <String>[];
    if (split.known.isNotEmpty) {
      final lines = split.known
          .map((t) => '  $t: ${ScoutConfig.reasonUnsupported(t)}')
          .join('\n');
      parts.add(
        'This app deliberately does not render these QRScout field '
        'types yet, so they became text boxes:\n$lines',
      );
    }
    if (split.unrecognised.isNotEmpty) {
      parts.add(
        'These field types are not recognised at all, which usually means '
        'QRScout added them after this app last looked: '
        '${split.unrecognised.join(', ')}. Worth reporting so they can be '
        'added.',
      );
    }
    return '\n\n${parts.join('\n\n')}\n\n'
        'Scouters will type into those fields instead of picking, and the '
        'values arrive as free text.';
  }

  Future<void> _editField(
    int sectionIdx,
    int fieldIdx,
    ScoutConfigField field,
  ) async {
    final titleCtrl = TextEditingController(text: field.title);
    final descCtrl = TextEditingController(text: field.description);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit field'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Code: ${field.code}   Type: ${field.type.displayName}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
    final newTitle = titleCtrl.text.trim();
    final newDesc = descCtrl.text.trim();
    titleCtrl.dispose();
    descCtrl.dispose();
    if (confirmed != true) return;

    final updated = field.copyWith(title: newTitle, description: newDesc);
    final sections = List<ScoutConfigSection>.from(_config.sections);
    final fields = List<ScoutConfigField>.from(sections[sectionIdx].fields);
    fields[fieldIdx] = updated;
    sections[sectionIdx] = sections[sectionIdx].copyWith(fields: fields);
    await _ctrl.updateConfig(_config.copyWith(sections: sections));
    if (!mounted) return;
    setState(() {
      _statusIsError = false;
      _statusMessage = 'Field "${updated.title}" updated.';
    });
  }

  Future<void> _exportJson() async {
    final json = const JsonEncoder.withIndent('  ').convert(_config.toJson());
    final controller = TextEditingController(text: json);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Current config JSON'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
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

  Future<void> _pitUploadJson() async {
    setState(() {
      _pitLoading = true;
      _pitStatusMessage = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted) return;
      if (result.isEmpty) {
        setState(() => _pitLoading = false);
        return;
      }
      final file = result.first;
      final bytes = await file.readAsBytes();
      final jsonString = utf8.decode(bytes);
      await _pitCtrl.loadFromJsonString(jsonString);
      if (!mounted) return;
      setState(() {
        _pitLoading = false;
        _pitStatusIsError = false;
        _pitStatusMessage =
            'Config loaded: "${_pitConfig.title}" with '
            '${_pitConfig.allFields.length} fields across '
            '${_pitConfig.sections.length} sections.'
            '${_unsupportedTypeWarning(_pitConfig)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pitLoading = false;
        _pitStatusIsError = true;
        _pitStatusMessage = 'Failed to load config: $e';
      });
    }
  }

  Future<void> _pitPasteJson() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste pit form JSON config'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Paste QRScout-compatible JSON here...',
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
            child: const Text('Load'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    if (text.isEmpty) return;

    setState(() {
      _pitLoading = true;
      _pitStatusMessage = null;
    });
    try {
      await _pitCtrl.loadFromJsonString(text);
      if (!mounted) return;
      setState(() {
        _pitLoading = false;
        _pitStatusIsError = false;
        _pitStatusMessage =
            'Config loaded: "${_pitConfig.title}" with '
            '${_pitConfig.allFields.length} fields.'
            '${_unsupportedTypeWarning(_pitConfig)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pitLoading = false;
        _pitStatusIsError = true;
        _pitStatusMessage = 'Failed to load config: $e';
      });
    }
  }

  Future<void> _pitExportJson() async {
    final json = const JsonEncoder.withIndent('  ')
        .convert(_pitConfig.toJson());
    final controller = TextEditingController(text: json);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Current pit form config JSON'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _ctrl,
        _themeCtrl,
        _eventCtrl,
        _roleCtrl,
        _pitCtrl,
      ]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Event', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Select your event to load team rosters, EPA stats, and match '
              'schedule for scouting and prematch analysis.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _eventCtrl.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: _openEventPicker,
                            icon: const Icon(Icons.search_rounded),
                            label: Text(
                              _eventCtrl.hasEvent
                                  ? 'Change event'
                                  : 'Select event',
                            ),
                          ),
                    if (_eventCtrl.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _eventCtrl.error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _eventCtrl.refresh(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                        ),
                      ),
                    ] else if (_eventCtrl.hasEvent) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Event',
                        value: _eventCtrl.eventName.isNotEmpty
                            ? _eventCtrl.eventName
                            : _eventCtrl.eventKey,
                      ),
                      _InfoRow(label: 'Key', value: _eventCtrl.eventKey),
                      _InfoRow(
                        label: 'Teams',
                        value: _eventCtrl.teamEvents.length.toString(),
                      ),
                      _InfoRow(
                        label: 'Matches',
                        value: _eventCtrl.matches.length.toString(),
                      ),
                      if (_eventCtrl.dataNotice != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _eventCtrl.dataNotice!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Your team', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Your own robot number. The trait table uses it to '
              'tell your alliance from the opponents\' in a match.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _MyTeamNumberField(eventController: _eventCtrl),
              ),
            ),
            const SizedBox(height: 24),
            Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    for (final mode in ThemeMode.values)
                      ButtonSegment<ThemeMode>(
                        value: mode,
                        label: SegmentLabel(_themeModeLabel(mode)),
                        icon: Icon(_themeModeIcon(mode)),
                      ),
                  ],
                  selected: {_themeCtrl.themeMode},
                  onSelectionChanged: (s) => _themeCtrl.setThemeMode(s.first),
                ),
              ),
            ),
            if (widget.onReplayTour != null || _canReport) ...[
              const SizedBox(height: 24),
              Text('Help', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (widget.onReplayTour != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'New to the app or showing a teammate around? '
                            'Replay the welcome tour.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: widget.onReplayTour,
                          child: const Text('Replay tour'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_canReport) ...[
                if (widget.onReplayTour != null) const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Hit a bug or have feedback? Send a report to the '
                            'app team. Your device details are attached to help '
                            'us debug.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _reportProblem,
                          icon: const Icon(Icons.bug_report_outlined, size: 18),
                          label: const Text('Report a problem'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Scout Configuration',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),

                const DocHelpButton(
                  docAsset: 'docs/admin-manual.md',
                  tooltip: 'Open the admin manual',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _canEdit
                  ? 'Upload a QRScout-compatible JSON file to customize the '
                        'scouting form. Changes are automatically synced to '
                        'all signed-in team members.'
                  : 'Your scouting config is managed by your team admin and '
                        'updates automatically when connected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_statusMessage != null)
              _StatusCard(message: _statusMessage!, isError: _statusIsError),
            if (_statusMessage != null) const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Active config',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Title', value: _config.title),
                    if (_config.pageTitle.isNotEmpty)
                      _InfoRow(label: 'Subtitle', value: _config.pageTitle),
                    _InfoRow(
                      label: 'Sections',
                      value: _config.sections.length.toString(),
                    ),
                    _InfoRow(
                      label: 'Total fields',
                      value: _config.allFields.length.toString(),
                    ),
                    _InfoRow(
                      label: 'Delimiter',
                      value: _config.delimiter == '\t'
                          ? 'Tab'
                          : _config.delimiter,
                    ),
                  ],
                ),
              ),
            ),
            if (_canEdit) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Load config',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        FilledButton.icon(
                          onPressed: _uploadJson,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Upload JSON file'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pasteJson,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: const Text('Paste JSON'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _exportJson,
                          icon: const Icon(Icons.code_rounded),
                          label: const Text('View current JSON'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            if (_canEditAccuracyMapping && _firebaseReady) ...[
              const SizedBox(height: 24),
              const AccuracyMappingSection(),
            ],

            if (_isAdmin && _firebaseReady) ...[
              const SizedBox(height: 24),
              const SheetsExportSection(),
            ],
            const SizedBox(height: 24),
            Text(
              'Pit Scouting Form',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _canEdit
                  ? 'Add, remove, reorder, and edit questions below, or '
                        'upload a QRScout-compatible JSON file for a full '
                        'form replacement. Changes are automatically synced '
                        'to all signed-in team members.'
                  : 'Your pit scouting form is managed by your team admin '
                        'and updates automatically when connected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_pitStatusMessage != null)
              _StatusCard(
                message: _pitStatusMessage!,
                isError: _pitStatusIsError,
              ),
            if (_pitStatusMessage != null) const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Active pit config',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Title', value: _pitConfig.title),
                    _InfoRow(
                      label: 'Sections',
                      value: _pitConfig.sections.length.toString(),
                    ),
                    _InfoRow(
                      label: 'Total fields',
                      value: _pitConfig.allFields.length.toString(),
                    ),
                  ],
                ),
              ),
            ),
            if (_canEdit) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Load pit config',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (_pitLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        FilledButton.icon(
                          onPressed: _pitUploadJson,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Upload JSON file'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pitPasteJson,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: const Text('Paste JSON'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pitExportJson,
                          icon: const Icon(Icons.code_rounded),
                          label: const Text('View current JSON'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              PitQuestionEditor(controller: _pitCtrl),
            ],
            const SizedBox(height: 16),
            Text('Fields', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._buildFieldList(),
            const SizedBox(height: 24),
            Text('About', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'App version, build, and device details. These are the same '
              'details attached to a problem report, so you can read them off '
              'here when asking for help.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _TelemetryTile(service: widget.telemetryService),
            const SizedBox(height: 12),
            const _DebugInfoCard(),
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              const _WebChannelTile(),
            ],
            if (_isDesktopPlatform) ...[
              const SizedBox(height: 12),
              const _LauncherTile(),
              const SizedBox(height: 12),
              const _DesktopUpdateTile(),
              const SizedBox(height: 24),
              Text(
                'Local AI assistant',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Offline fallback for the AI features, answered by a model '
                'that runs entirely on this computer instead of the network.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const AssistantSetupCard(),
            ],
          ],
        );
      },
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
    }
  }

  List<Widget> _buildFieldList() {
    final widgets = <Widget>[];
    for (var si = 0; si < _config.sections.length; si++) {
      final section = _config.sections[si];
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            section.name,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );
      widgets.add(
        Card(
          child: Column(
            children: [
              for (var fi = 0; fi < section.fields.length; fi++)
                _buildFieldTile(si, fi, section.fields[fi]),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildFieldTile(int si, int fi, ScoutConfigField field) {
    return ListTile(
      title: Text(field.title),
      subtitle: Text(
        '${field.type.displayName}  |  code: ${field.code}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: _canEdit
          ? IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit field',
              onPressed: () => _editField(si, fi, field),
            )
          : null,
    );
  }
}

class _MyTeamNumberField extends StatefulWidget {
  const _MyTeamNumberField({required this.eventController});

  final EventController eventController;

  @override
  State<_MyTeamNumberField> createState() => _MyTeamNumberFieldState();
}

class _MyTeamNumberFieldState extends State<_MyTeamNumberField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.eventController.myTeamNumber?.toString() ?? '',
  );

  @override
  void dispose() {
    _save();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _text.text.trim();
    final parsed = trimmed.isEmpty ? null : int.tryParse(trimmed);

    if (trimmed.isNotEmpty && parsed == null) return;
    widget.eventController.setMyTeamNumber(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        labelText: 'Team number',
        hintText: 'e.g. 3847',
      ),
      onSubmitted: (_) => _save(),
      onTapOutside: (_) => _save(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
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

bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

class _LauncherTile extends StatefulWidget {
  const _LauncherTile();

  @override
  State<_LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<_LauncherTile> {
  final DesktopLauncherService _service = DesktopLauncherService();
  bool _working = false;
  String? _status;

  Future<void> _register() async {
    setState(() {
      _working = true;
      _status = null;
    });
    try {
      await _service.registerInLauncher();
      if (!mounted) return;
      setState(() => _status = 'Added to your applications menu.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not add it to the menu.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Applications menu',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Add Spectrum Strategy to your desktop applications menu so it '
              'shows up in search. Run this once after downloading a new build.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _working ? null : _register,
                icon: _working
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.apps_rounded, size: 18),
                label: const Text('Add to applications menu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebChannelTile extends StatefulWidget {
  const _WebChannelTile();

  @override
  State<_WebChannelTile> createState() => _WebChannelTileState();
}

class _WebChannelTileState extends State<_WebChannelTile> {
  final WebChannelService _service = WebChannelService();
  bool _switching = false;
  String? _status;

  WebChannel? get _current => WebChannelService.channelForHost(Uri.base.host);

  Future<void> _switchTo(WebChannel channel) async {
    if (_switching || channel == _current) return;
    setState(() {
      _switching = true;
      _status = 'Checking the ${channel.label.toLowerCase()} site...';
    });
    final available = await _service.hasPublishedBuild(channel);
    if (!mounted) return;
    if (!available) {
      setState(() {
        _switching = false;
        _status =
            'The ${channel.label.toLowerCase()} site has no build '
            'published yet.';
      });
      return;
    }
    setState(
      () => _status = 'Opening the ${channel.label.toLowerCase()} site...',
    );
    final launched = await launchUrl(channel.url, webOnlyWindowName: '_self');
    if (!mounted) return;
    setState(() {
      _switching = false;
      if (!launched) {
        _status =
            'Could not open the ${channel.label.toLowerCase()} site. '
            'Try again, or navigate to it directly.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Web channel', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Stable follows published releases; staging follows every '
              'change as it lands. Switching opens the other site.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<WebChannel>(
              segments: [
                for (final channel in WebChannel.values)
                  ButtonSegment(
                    value: channel,
                    label: SegmentLabel(channel.label),
                  ),
              ],
              selected: {?current},
              emptySelectionAllowed: current == null,
              onSelectionChanged: _switching ? null : (s) => _switchTo(s.first),
              showSelectedIcon: false,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          ],
        ),
      ),
    );
  }
}

class _DesktopUpdateTile extends StatefulWidget {
  const _DesktopUpdateTile();

  @override
  State<_DesktopUpdateTile> createState() => _DesktopUpdateTileState();
}

class _DesktopUpdateTileState extends State<_DesktopUpdateTile> {
  final DesktopUpdateService _service = DesktopUpdateService();
  final DesktopSelfUpdateService _selfUpdate = DesktopSelfUpdateService();
  bool _checking = false;
  bool _installing = false;
  String? _status;
  DesktopUpdateInfo? _update;
  DesktopUpdateChannel _channel = DesktopUpdateChannel.stable;

  @override
  void initState() {
    super.initState();
    _service
        .currentChannel()
        .then((channel) {
          if (mounted) setState(() => _channel = channel);
        })
        .catchError((Object error) {
          debugPrint('Update channel read failed: $error');
        });
  }

  bool get _canInstall =>
      _update?.assetUrl != null && _selfUpdate.canSelfUpdate;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      final channel = await _service.currentChannel();
      final result = await _service.checkForUpdate(channel: channel);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _applyResult(result, channel);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _switchChannel(DesktopUpdateChannel channel) async {
    setState(() {
      _channel = channel;
      _checking = true;
      _status = null;
      _update = null;
    });
    try {
      await _service.setChannel(channel);
      final result = await _service.checkForUpdate(
        channel: channel,
        ignoreVersionGate: true,
      );
      if (!mounted) return;
      setState(() => _applyResult(result, channel));
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not check for updates right now.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _applyResult(DesktopUpdateCheck result, DesktopUpdateChannel channel) {
    _update = result.update;
    if (result.update != null) {
      _status = 'Update available: ${result.update!.latestVersion}.';
    } else if (result.hasRelease) {
      _status = 'You are on the latest version.';
    } else {
      _status =
          'No ${channel.name} build has been published yet, so there is '
          'nothing to update to.';
    }
  }

  Future<void> _openDownload() async {
    final info = _update;
    if (info == null) return;
    await launchUrl(info.releaseUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _install() async {
    final info = _update;
    final url = info?.assetUrl;
    final digest = info?.expectedSha256;
    if (url == null) return;
    if (digest == null || digest.isEmpty) {
      setState(() {
        _status =
            'This release has no checksum, so it cannot be installed '
            'automatically. Opening the download page.';
      });
      await launchUrl(info!.releaseUrl, mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      _installing = true;
      _status = 'Downloading update...';
    });
    try {
      await _selfUpdate.update(Uri.parse(url), expectedSha256: digest);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _status = 'Could not install automatically; opening the download page.';
      });
      await launchUrl(info!.releaseUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Desktop updates',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Desktop builds do not auto-update. Check for a newer release '
              'and download it when one is available.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<DesktopUpdateChannel>(
              segments: const [
                ButtonSegment(
                  value: DesktopUpdateChannel.stable,
                  label: SegmentLabel('Stable'),
                ),
                ButtonSegment(
                  value: DesktopUpdateChannel.nightly,
                  label: SegmentLabel('Nightly'),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: (_checking || _installing)
                  ? null
                  : (s) => _switchChannel(s.first),
              showSelectedIcon: false,
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_update != null)
                  FilledButton.icon(
                    onPressed: _installing
                        ? null
                        : (_canInstall ? _install : _openDownload),
                    icon: _installing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_canInstall ? 'Install update' : 'Get update'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (_checking || _installing) ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check for updates'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryTile extends StatefulWidget {
  const _TelemetryTile({this.service});

  final TelemetryService? service;

  @override
  State<_TelemetryTile> createState() => _TelemetryTileState();
}

class _TelemetryTileState extends State<_TelemetryTile> {
  late final TelemetryService _service = widget.service ?? TelemetryService();
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _service.isEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await _service.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Usage data', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Share anonymous usage data (app version, platform, and which '
              'tabs get opened) to help improve the app. No personal '
              'information or account details are collected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share anonymous usage data'),
              value: _enabled,
              onChanged: _toggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugInfoCard extends StatefulWidget {
  const _DebugInfoCard();

  @override
  State<_DebugInfoCard> createState() => _DebugInfoCardState();
}

class _DebugInfoCardState extends State<_DebugInfoCard> {
  late final Future<DebugInfo> _info = DebugInfo.gather();

  Future<void> _copy(DebugInfo info) async {
    await Clipboard.setData(ClipboardData(text: info.toDisplayText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Debug info copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<DebugInfo>(
          future: _info,
          builder: (context, snapshot) {
            final info = snapshot.data;
            if (info == null) {
              return Text(
                'Loading build info...',
                style: Theme.of(context).textTheme.bodySmall,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(label: 'App version', value: info.versionLabel),
                _InfoRow(label: 'Commit', value: info.commitLabel),
                if (info.gitBranch.isNotEmpty)
                  _InfoRow(label: 'Branch', value: info.gitBranch),
                if (info.buildDate.isNotEmpty)
                  _InfoRow(label: 'Built', value: info.buildDate),
                _InfoRow(label: 'Platform', value: info.platform),
                if (info.osVersion.isNotEmpty)
                  _InfoRow(label: 'OS', value: info.osVersion),
                if (info.device.isNotEmpty)
                  _InfoRow(label: 'Device', value: info.device),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _copy(info),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.message, required this.isError});

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
