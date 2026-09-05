import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/services/pit_photo_store.dart';
import '../scouting/services/pit_scouting_sync_service.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/ui/scout_form_fields.dart';
import '../state/failed_write_tracker.dart';
import '../theme/strategy_palette.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/sync_status_pill.dart';
import 'pit_database_view.dart';

class PitScoutingScreen extends StatefulWidget {
  const PitScoutingScreen({
    required this.controller,
    required this.configController,
    super.key,
  });

  final PitScoutingController controller;
  final PitScoutConfigController configController;

  @override
  State<PitScoutingScreen> createState() => _PitScoutingScreenState();
}

class _PitScoutingScreenState extends State<PitScoutingScreen> {
  final TextEditingController _teamNumberCtrl = TextEditingController();
  Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _textControllers = {};
  String? _statusMessage;
  bool _statusIsError = false;
  String _configFingerprint = '';

  ScoutConfig get _config => widget.configController.config;

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
    _teamNumberCtrl.dispose();
    for (final c in _textControllers.values) {
      c.dispose();
    }
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
          field.type == ScoutFieldType.number) {
        final ctrl = TextEditingController(
          text: _values[field.code]?.toString() ?? '',
        );
        ctrl.addListener(() {
          _values[field.code] = ctrl.text;
        });
        _textControllers[field.code] = ctrl;
      }
    }
  }

  void _setFieldValue(String code, dynamic value) {
    setState(() {
      _values[code] = value;
    });
  }

  void _resetForm() {
    setState(() {
      for (final field in _config.allFields) {
        _values[field.code] = field.effectiveDefault;
        _textControllers[field.code]?.text =
            field.effectiveDefault?.toString() ?? '';
      }
      _statusMessage = null;
      _statusIsError = false;
    });
  }

  Future<void> _saveEntry() async {
    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }

    final teamText = _teamNumberCtrl.text.trim();
    final teamNumber = int.tryParse(teamText) ?? 0;
    if (teamNumber <= 0) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Enter a valid team number before saving.';
      });
      return;
    }

    final existing = widget.controller.entriesForTeam(teamNumber).where((e) {
      final uid = widget.controller.currentUserUid;

      return e.authorUid.isEmpty || (uid != null && e.authorUid == uid);
    }).firstOrNull;

    final entry = (existing ?? PitScoutEntry(teamNumber: teamNumber)).copyWith(
      teamNumber: teamNumber,
      fieldValues: Map<String, dynamic>.from(_values),
    );

    final saved = await widget.controller.saveEntry(entry);
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _statusIsError = true;
        _statusMessage =
            widget.controller.lastError ??
            'Could not save the pit entry for team $teamNumber.';
      });
      widget.controller.clearLastError();
      return;
    }

    final pitSyncState = widget.controller.syncStatus.state;
    final syncEnabled =
        pitSyncState != PitScoutingSyncState.signedOut &&
        pitSyncState != PitScoutingSyncState.noAccess;

    setState(() {
      _statusIsError = false;
      _statusMessage = syncEnabled
          ? 'Pit entry for team $teamNumber submitted to team database.'
          : 'Pit entry for team $teamNumber saved locally. Sign in to sync.';
    });
    _resetForm();
    _teamNumberCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final questionnaireBody = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.configController,
      ]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSyncStatus(),
            if (widget.controller.failedWrites.hasFailures) ...[
              const SizedBox(height: 8),
              _PitScoutingSyncPill(
                failedWrites: widget.controller.failedWrites,
              ),
            ],
            const SizedBox(height: 12),
            _buildTeamNumberField(),
            const SizedBox(height: 16),
            ..._config.sections.map(
              (section) => ScoutFormSection(
                section: section,
                keyPrefix: 'pit-field',
                values: _values,
                textControllers: _textControllers,
                onFieldChanged: _setFieldValue,
              ),
            ),
            const SizedBox(height: 16),
            _buildActionButtons(),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              _buildStatusCard(),
            ],
            const SizedBox(height: 24),
            _buildEntriesList(),
          ],
        );
      },
    );

    final content = SaveShortcut(onSave: _saveEntry, child: questionnaireBody);

    final tabs = <Tab>[
      const Tab(text: 'Database'),
      const Tab(text: 'Questionnaire'),
    ];
    final tabViews = <Widget>[
      PitDatabaseView(
        controller: widget.controller,
        configController: widget.configController,
      ),
      content,
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pit Scouting'),
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        body: TabBarView(children: tabViews),
      ),
    );
  }

  Widget _buildSyncStatus() {
    final status = widget.controller.syncStatus;
    final (String label, IconData icon) = switch (status.state) {
      PitScoutingSyncState.signedOut => (
        'Not signed in to sync',
        Icons.cloud_off_rounded,
      ),
      PitScoutingSyncState.noAccess => (
        'No team access yet',
        Icons.lock_outline_rounded,
      ),
      PitScoutingSyncState.syncing => ('Syncing...', Icons.sync_rounded),
      PitScoutingSyncState.synced => ('Synced', Icons.cloud_done_rounded),
      PitScoutingSyncState.offline => ('Offline', Icons.cloud_off_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),

          Flexible(child: Text(label)),
        ],
      ),
    );
  }

  Widget _buildTeamNumberField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Team Number',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _teamNumberCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: const InputDecoration(
            hintText: 'e.g. 3847',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _saveEntry,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save pit entry'),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () {
            _resetForm();
            _teamNumberCtrl.clear();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: _statusIsError
          ? StrategyPalette.surfaceStrongOf(context)
          : StrategyPalette.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _statusIsError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 16,
              color: _statusIsError
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _statusIsError
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesList() {
    final entries = widget.controller.entries;
    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pit entries',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('No pit entries saved yet.'),
            ],
          ),
        ),
      );
    }

    final byTeam = <int, List<PitScoutEntry>>{};
    for (final entry in entries) {
      byTeam.putIfAbsent(entry.teamNumber, () => <PitScoutEntry>[]).add(entry);
    }
    final sortedTeams = byTeam.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pit entries', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final team in sortedTeams) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  'Team $team',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              ...byTeam[team]!.map((entry) => _buildEntryTile(entry)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntryTile(PitScoutEntry entry) {
    final myUid = widget.controller.currentUserUid;
    final isOwn = entry.authorUid.isEmpty || entry.authorUid == myUid;
    final authorLabel = entry.authorDisplayName.isNotEmpty
        ? entry.authorDisplayName
        : entry.authorUid.isNotEmpty
        ? entry.authorUid
        : 'Offline entry';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${entry.fieldValues.length} fields recorded'),
          if (_visiblePhotoIds(entry).isNotEmpty) _buildPhotoStrip(entry),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOwn ? 'You' : authorLabel,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (isOwn) _buildPhotoControls(entry),
        ],
      ),
      trailing: isOwn
          ? IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete entry',
              onPressed: () => _confirmDeleteEntry(entry),
            )
          : const Icon(Icons.lock_outline_rounded, size: 18),
    );
  }

  final Map<String, Future<Uint8List?>> _photoBytes =
      <String, Future<Uint8List?>>{};

  Future<Uint8List?> _bytesFor(PitScoutEntry entry, String photoId) {
    return _photoBytes.putIfAbsent(
      '${entry.id}/$photoId',
      () => widget.controller.photoBytes(entry, photoId),
    );
  }

  List<String> _visiblePhotoIds(PitScoutEntry entry) {
    final hasStore = widget.controller.photoStore != null;
    final hasUploader = widget.controller.photoUploader != null;
    if (hasStore && entry.photoIds.isNotEmpty) return entry.photoIds;

    if (!hasUploader) return const <String>[];
    if (entry.photoIds.isNotEmpty) return entry.photoIds;
    return entry.photoKeys.values.toList(growable: false);
  }

  Widget _buildPhotoStrip(PitScoutEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final photoId in _visiblePhotoIds(entry))
            _buildThumbnail(entry, photoId),
        ],
      ),
    );
  }

  Widget _buildThumbnail(PitScoutEntry entry, String photoId) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _bytesFor(entry, photoId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;

        final failed =
            snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done && bytes == null);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () => _showFullPhoto(entry, photoId),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: StrategyPalette.surfaceStrongOf(context),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(StrategyPalette.radiusSm),
                  ),
                ),
                child: bytes != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(StrategyPalette.radiusSm),
                        ),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          width: 64,
                          height: 64,
                        ),
                      )
                    : failed
                    ? Icon(
                        Icons.broken_image_rounded,
                        size: 24,
                        color: colorScheme.error,
                      )
                    : const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            ),
            Positioned(
              top: -4,
              right: -4,
              child: GestureDetector(
                onTap: () => _removePhoto(entry, photoId),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colorScheme.onError,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPhotoControls(PitScoutEntry entry) {
    if (widget.controller.photoStore == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Pit photos are not supported on web; the web build is for '
          'debugging only. Run the app on a phone, tablet, or desktop to add '
          'photos.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return _buildCaptureButton(entry);
  }

  Widget _buildCaptureButton(PitScoutEntry entry) {
    if (entry.photoIds.length >= PitScoutEntry.maxPhotos) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => _capturePhoto(entry, PhotoSource.camera),
            icon: const Icon(Icons.camera_alt_rounded, size: 16),
            label: const Text('Camera'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: () => _capturePhoto(entry, PhotoSource.gallery),
            icon: const Icon(Icons.photo_library_rounded, size: 16),
            label: const Text('Gallery'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _capturePhoto(PitScoutEntry entry, PhotoSource source) async {
    try {
      final photoId = await widget.controller.photoStore!.capture(
        entryId: entry.id,
        source: source,
      );
      if (!mounted) return;
      final updated = entry.withAddedPhoto(photoId);
      if (!await widget.controller.saveEntry(updated)) {
        if (!mounted) return;
        setState(() {
          _statusIsError = true;
          _statusMessage =
              widget.controller.lastError ??
              'The photo was taken but could not be attached to the entry.';
        });
        widget.controller.clearLastError();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Failed to capture photo: $e';
      });
    }
  }

  Future<void> _removePhoto(PitScoutEntry entry, String photoId) async {
    _photoBytes.remove('${entry.id}/$photoId');

    await widget.controller.removePhoto(entry, photoId);
  }

  void _showFullPhoto(PitScoutEntry entry, String photoId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _FullPhotoView(bytes: widget.controller.photoBytes(entry, photoId)),
      ),
    );
  }

  Future<void> _confirmDeleteEntry(PitScoutEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete pit entry?'),
          content: Text(
            'This will remove the pit entry for team ${entry.teamNumber}, '
            'including from the shared database.',
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
    final deleted = await widget.controller.deleteEntry(entry.id);
    if (!mounted || deleted) return;
    setState(() {
      _statusIsError = true;
      _statusMessage =
          widget.controller.lastError ??
          'Could not delete that pit entry. It is still saved on this device.';
    });
    widget.controller.clearLastError();
  }
}

class _PitScoutingSyncPill extends StatelessWidget {
  const _PitScoutingSyncPill({required this.failedWrites});

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

class _FullPhotoView extends StatelessWidget {
  const _FullPhotoView({required this.bytes});

  final Future<Uint8List?> bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: FutureBuilder<Uint8List?>(
          future: bytes,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return snapshot.connectionState == ConnectionState.done ||
                      snapshot.hasError
                  ? const Icon(Icons.broken_image_rounded, size: 48)
                  : const CircularProgressIndicator();
            }
            return InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }
}
