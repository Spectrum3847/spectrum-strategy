import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/services/pit_photo_capture.dart';
import '../scouting/services/pit_photo_store.dart';
import '../scouting/services/pit_scouting_sync_service.dart';
import '../scouting/state/pit_scout_config_controller.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../scouting/ui/scout_form_fields.dart';
import '../state/failed_write_tracker.dart';
import '../theme/strategy_palette.dart';
import '../widgets/glass_modal.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/sync_status_pill.dart';
import 'pit_database_view.dart';
import 'tab_swipe.dart';

class PitScoutingScreen extends StatefulWidget {
  const PitScoutingScreen({
    required this.controller,
    required this.configController,
    required this.canEditAnyEntry,
    super.key,
  });

  final PitScoutingController controller;
  final PitScoutConfigController configController;

  final bool canEditAnyEntry;

  @override
  State<PitScoutingScreen> createState() => _PitScoutingScreenState();
}

class _PitScoutingScreenState extends State<PitScoutingScreen> {
  final TextEditingController _teamNumberCtrl = TextEditingController();
  final FocusNode _teamNumberFocus = FocusNode();
  Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _textControllers = {};
  String? _statusMessage;
  bool _statusIsError = false;
  String _configFingerprint = '';

  final List<Uint8List> _pendingPhotos = <Uint8List>[];

  bool _saving = false;

  String? _editingEntryId;

  bool _dirty = false;

  PitScoutEntry? _loadOffer;

  ScoutConfig get _config => widget.configController.config;

  @override
  void initState() {
    super.initState();
    widget.configController.addListener(_onConfigChanged);

    _teamNumberCtrl.addListener(_onTeamNumberChanged);

    _teamNumberFocus.addListener(_onTeamNumberFocusChanged);
    _initValues(_config);
    _configFingerprint = jsonEncode(_config.toJson());
  }

  @override
  void dispose() {
    widget.configController.removeListener(_onConfigChanged);
    _teamNumberCtrl.removeListener(_onTeamNumberChanged);
    _teamNumberFocus.removeListener(_onTeamNumberFocusChanged);
    _teamNumberFocus.dispose();
    _teamNumberCtrl.dispose();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTeamNumberChanged() {
    if (widget.controller.photoStore == null) return;
    setState(() {});
  }

  void _onTeamNumberFocusChanged() {
    if (!_teamNumberFocus.hasFocus) _resolveTeamNumber();
  }

  void _resolveTeamNumber() {
    final existing = _targetEntry();
    if (existing == null || existing.id == _editingEntryId) return;
    if (_dirty) {
      setState(() => _loadOffer = existing);
      return;
    }
    _loadEntryIntoForm(existing);
  }

  void _loadEntryIntoForm(PitScoutEntry entry) {
    setState(() {
      _loadOffer = null;
      _editingEntryId = entry.id;
      _teamNumberCtrl.text = entry.teamNumber.toString();
      for (final field in _config.allFields) {
        final saved = entry.fieldValues[field.code];

        final value = saved ?? field.effectiveDefault;
        _values[field.code] = value;
        _textControllers[field.code]?.text = value?.toString() ?? '';
      }

      _dirty = false;
      _statusIsError = false;
      _statusMessage = null;
    });
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
          field.type == ScoutFieldType.longText ||
          field.type == ScoutFieldType.number) {
        final ctrl = TextEditingController(
          text: _values[field.code]?.toString() ?? '',
        );
        ctrl.addListener(() {
          if (_values[field.code] != ctrl.text) _dirty = true;
          _values[field.code] = ctrl.text;
        });
        _textControllers[field.code] = ctrl;
      }
    }
  }

  void _setFieldValue(String code, dynamic value) {
    setState(() {
      _dirty = true;
      _values[code] = value;
    });
  }

  Future<void> _discardWritten(
    PitPhotoStore store,
    String entryId,
    List<String> photoIds,
  ) async {
    for (final photoId in photoIds) {
      try {
        await store.delete(entryId, photoId);
      } catch (_) {}
    }
    photoIds.clear();
  }

  void _resetForm() {
    setState(() {
      _pendingPhotos.clear();
      _editingEntryId = null;
      _loadOffer = null;
      _dirty = false;
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
    if (_saving) return;
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

    setState(() => _saving = true);
    try {
      await _saveResolvedEntry(teamNumber);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  PitScoutEntry? _targetEntry() {
    final teamNumber = int.tryParse(_teamNumberCtrl.text.trim()) ?? 0;
    if (teamNumber <= 0) return null;
    return _ownEntryForTeam(teamNumber);
  }

  PitScoutEntry? _ownEntryForTeam(int teamNumber) {
    return widget.controller.entriesForTeam(teamNumber).where((e) {
      final uid = widget.controller.currentUserUid;

      return e.authorUid.isEmpty || (uid != null && e.authorUid == uid);
    }).firstOrNull;
  }

  Future<void> _saveResolvedEntry(int teamNumber) async {
    final existing = _ownEntryForTeam(teamNumber);

    final currentUid = widget.controller.currentUserUid;
    final currentDisplayName = widget.controller.currentUserDisplayName;
    final needsAuthor = existing == null || existing.authorUid.isEmpty;
    var entry = (existing ?? PitScoutEntry(teamNumber: teamNumber)).copyWith(
      teamNumber: teamNumber,
      fieldValues: Map<String, dynamic>.from(_values),
      authorUid: needsAuthor && currentUid != null ? currentUid : null,
      authorDisplayName: needsAuthor && currentDisplayName != null
          ? currentDisplayName
          : null,
    );

    final written = <String>[];
    final store = widget.controller.photoStore;
    final staged = List<Uint8List>.of(_pendingPhotos);
    var dropped = 0;
    if (store != null) {
      for (final bytes in staged) {
        if (entry.photoIds.length >= PitScoutEntry.maxPhotos) {
          dropped++;
          continue;
        }
        try {
          final photoId = await store.write(entry.id, bytes);
          written.add(photoId);
          entry = entry.withAddedPhoto(photoId);
        } catch (error) {
          await _discardWritten(store, entry.id, written);
          if (!mounted) return;
          setState(() {
            _statusIsError = true;
            _statusMessage = 'Could not save the photos: $error';
          });
          return;
        }
      }
    }

    final saved = await widget.controller.saveEntry(entry);
    if (!saved) {
      if (store != null) await _discardWritten(store, entry.id, written);
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage =
            widget.controller.lastError ??
            'Could not save the pit entry for team $teamNumber.';
      });
      widget.controller.clearLastError();
      return;
    }
    if (!mounted) return;

    final pitSyncState = widget.controller.syncStatus.state;
    final syncEnabled =
        pitSyncState != PitScoutingSyncState.signedOut &&
        pitSyncState != PitScoutingSyncState.noAccess;

    final dropNote = dropped == 0
        ? ''
        : ' $dropped photo${dropped == 1 ? '' : 's'} could not be added: '
              'team $teamNumber already has '
              '${PitScoutEntry.maxPhotos} of them.';
    setState(() {
      _statusIsError = dropped > 0;
      _statusMessage =
          (syncEnabled
              ? 'Pit entry for team $teamNumber submitted to team database.'
              : 'Pit entry for team $teamNumber saved locally. '
                    'Sign in to sync.') +
          dropNote;
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
            if (_loadOffer != null) ...[
              const SizedBox(height: 8),
              _buildLoadOffer(),
            ] else if (_editingEntryId != null) ...[
              const SizedBox(height: 8),
              _buildEditingNotice(),
            ],
            const SizedBox(height: 16),
            ..._config.sections.map(
              (section) => ScoutFormSection(
                section: section,
                keyPrefix: 'pit-field',
                values: _values,
                textControllers: _textControllers,
                onFieldChanged: _setFieldValue,
                documentUploader: widget.controller.photoUploader,
              ),
            ),
            if (widget.controller.photoStore != null) _buildPhotoSection(),
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
        body: TabBarView(physics: tabSwipePhysics, children: tabViews),
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

  Widget _buildEditingNotice() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 16,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Editing your saved entry for this team. Saving updates it.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadOffer() {
    final theme = Theme.of(context);
    final offer = _loadOffer!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: const BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You already have an entry for team ${offer.teamNumber}. Saving '
            'will replace its answers with what is in this form.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _loadEntryIntoForm(offer),
                child: const Text('Load saved answers'),
              ),
              TextButton(
                onPressed: () => setState(() => _loadOffer = null),
                child: const Text('Keep what I typed'),
              ),
            ],
          ),
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
          focusNode: _teamNumberFocus,
          onSubmitted: (_) => _resolveTeamNumber(),
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: const InputDecoration(
            hintText: 'e.g. 3847',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoSection() {
    final theme = Theme.of(context);

    final alreadyFiled = _targetEntry()?.photoIds.length ?? 0;
    final remaining =
        PitScoutEntry.maxPhotos - alreadyFiled - _pendingPhotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Photos',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _pendingPhotos.isEmpty
                      ? 'Up to ${PitScoutEntry.maxPhotos} photos of the robot. '
                            'They are attached when you save the entry.'
                      : '${_pendingPhotos.length} of '
                            '${PitScoutEntry.maxPhotos} added, attached when '
                            'you save.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_pendingPhotos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPendingThumbnails(),
                ],
                const SizedBox(height: 12),
                _buildPendingCaptureButtons(enabled: remaining > 0 && !_saving),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPendingThumbnails() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _pendingPhotos.length; i++)
          _PendingPhotoThumbnail(
            bytes: _pendingPhotos[i],

            onRemove: () => setState(() => _pendingPhotos.removeAt(i)),
            onView: () => _showPendingPhoto(_pendingPhotos[i]),
          ),
      ],
    );
  }

  Widget _buildPendingCaptureButtons({required bool enabled}) {
    final sources = <(PhotoSource, IconData, String)>[
      (PhotoSource.camera, Icons.camera_alt_rounded, 'Camera'),
      (PhotoSource.gallery, Icons.photo_library_rounded, 'Gallery'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (source, icon, label) in sources)
          OutlinedButton.icon(
            onPressed: enabled ? () => _stagePhoto(source) : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
      ],
    );
  }

  Future<void> _stagePhoto(PhotoSource source) async {
    try {
      final bytes = await pickAndCompressPhoto(source);
      if (!mounted) return;
      setState(() {
        if (_pendingPhotos.length < PitScoutEntry.maxPhotos) {
          _pendingPhotos.add(bytes);
        }
        _statusMessage = null;
        _statusIsError = false;
      });
    } on StateError {
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Failed to add photo: $error';
      });
    }
  }

  void _showPendingPhoto(Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Photo')),
          backgroundColor: Colors.black,
          body: Center(child: Image.memory(bytes)),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveEntry,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save pit entry'),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () {
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
    final canDelete = isOwn || widget.canEditAnyEntry;
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
          if (isOwn) _buildEditAction(entry),
        ],
      ),
      trailing: canDelete
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

  Widget _buildEditAction(PitScoutEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _saving ? null : () => _loadEntryIntoForm(entry),
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: const Text('Edit in the form above'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
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
    final confirmed = await showGlassConfirmDialog<bool>(
      context: context,
      title: 'Delete pit entry?',
      content: Text(
        'This will remove the pit entry for team ${entry.teamNumber}, '
        'including from the shared database.',
      ),
      actionsBuilder: (dialogContext) => [
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

class _PendingPhotoThumbnail extends StatelessWidget {
  const _PendingPhotoThumbnail({
    required this.bytes,
    required this.onRemove,
    required this.onView,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(StrategyPalette.radiusSm),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
        ),

        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            onPressed: onRemove,
            tooltip: 'Remove photo',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
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
