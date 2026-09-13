import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/services/document_attachment_actions.dart';
import '../scouting/services/pit_photo_upload_service.dart';
import '../scouting/services/scout_field_display.dart';
import '../scouting/state/pit_scouting_controller.dart';
import '../theme/strategy_palette.dart';

class PitEntryCard extends StatefulWidget {
  const PitEntryCard({
    required this.entry,
    required this.controller,
    required this.config,
    this.initiallyExpanded = false,
    this.openDocument = openDocumentBytes,
    super.key,
  });

  final PitScoutEntry entry;
  final PitScoutingController controller;
  final ScoutConfig config;

  final bool initiallyExpanded;

  final Future<void> Function(Uint8List bytes, String workerKey) openDocument;

  @override
  State<PitEntryCard> createState() => _PitEntryCardState();
}

class _PitEntryCardState extends State<PitEntryCard> {
  final Map<String, Future<Uint8List?>> _photoBytes =
      <String, Future<Uint8List?>>{};

  Future<Uint8List?> _bytesFor(String photoId) {
    return _photoBytes.putIfAbsent(
      photoId,
      () => widget.controller.photoBytes(widget.entry, photoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: colorScheme.primary,
          child: Text(
            entry.teamNumber > 0 ? entry.teamNumber.toString() : '?',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        title: Text(
          entry.teamNumber > 0 ? 'Team ${entry.teamNumber}' : 'Unknown team',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                _InfoRow(
                  label: 'Scouted by',
                  value: entry.authorDisplayName.isEmpty
                      ? 'Offline entry'
                      : entry.authorDisplayName,
                ),
                _InfoRow(
                  label: 'Last updated',
                  value: _formatDateTime(entry.updatedAt.toLocal()),
                ),
                if (_questionRows.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Questions',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._questionRows,
                ],

                const SizedBox(height: 8),
                const Divider(),
                Text(
                  'Photos',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                _buildPhotos(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> get _questionRows {
    final config = widget.config;
    final fieldByCode = {for (final f in config.allFields) f.code: f};
    final present = widget.entry.fieldValues.keys.toSet();
    final ordered = <String>[
      for (final field in config.allFields)
        if (present.contains(field.code)) field.code,
    ];
    final unknown = present.difference(ordered.toSet()).toList()..sort();
    return [
      for (final code in [...ordered, ...unknown])
        if (fieldByCode[code]?.type == ScoutFieldType.document)
          _AttachmentRow(
            label: fieldByCode[code]?.title ?? code,
            workerKey: widget.entry.fieldValues[code]?.toString() ?? '',
            uploader: widget.controller.photoUploader,
            openDocument: widget.openDocument,
          )
        else
          _InfoRow(
            label: fieldByCode[code]?.title ?? code,
            value: displayFieldValue(
              fieldByCode[code],
              widget.entry.fieldValues[code],
            ),
          ),
    ];
  }

  List<String> get _photoSlots {
    final entry = widget.entry;
    if (entry.photoIds.isNotEmpty) return entry.photoIds;
    if (entry.photoKeys.isNotEmpty) {
      return entry.photoKeys.keys.toList(growable: false);
    }
    return const <String>[];
  }

  Widget _buildPhotos(BuildContext context) {
    final slots = _photoSlots;
    if (slots.isEmpty) {
      return Text(
        'No photos submitted with this entry.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: _mutedColor(context)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final photoId in slots) _buildThumbnail(photoId)],
    );
  }

  Color _mutedColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  Widget _buildThumbnail(String photoId) {
    return FutureBuilder<Uint8List?>(
      future: _bytesFor(photoId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        final done = snapshot.connectionState == ConnectionState.done;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: const BorderRadius.all(
              Radius.circular(StrategyPalette.radiusSm),
            ),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: 64,
              height: 64,
            ),
          );
        }
        if (!done) {
          return Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: StrategyPalette.surfaceStrongOf(context),
              borderRadius: const BorderRadius.all(
                Radius.circular(StrategyPalette.radiusSm),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }

        return Tooltip(
          message:
              'Not available on this device. This photo lives on the '
              'device that captured it, or in the team photo storage once '
              'synced.',
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: StrategyPalette.surfaceStrongOf(context),
              borderRadius: const BorderRadius.all(
                Radius.circular(StrategyPalette.radiusSm),
              ),
            ),
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 24,
              color: _mutedColor(context),
            ),
          ),
        );
      },
    );
  }

  String get _subtitle {
    final entry = widget.entry;
    final parts = <String>[];
    if (entry.fieldValues.isNotEmpty) {
      parts.add('${entry.fieldValues.length} fields');
    }
    final photoCount = _photoSlots.length;
    if (photoCount > 0) {
      parts.add(photoCount == 1 ? '1 photo' : '$photoCount photos');
    }
    return parts.isEmpty ? 'No fields recorded' : parts.join(' · ');
  }

  String _formatDateTime(DateTime dt) {
    final d = '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
    final t = '${_pad(dt.hour)}:${_pad(dt.minute)}';
    return '$d $t';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _AttachmentRow extends StatefulWidget {
  const _AttachmentRow({
    required this.label,
    required this.workerKey,
    required this.uploader,
    required this.openDocument,
  });

  final String label;
  final String workerKey;

  final PitPhotoUploadService? uploader;

  final Future<void> Function(Uint8List bytes, String workerKey) openDocument;

  @override
  State<_AttachmentRow> createState() => _AttachmentRowState();
}

class _AttachmentRowState extends State<_AttachmentRow> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    final uploader = widget.uploader;
    if (uploader == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await uploader.download(widget.workerKey);
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _busy = false;
          _error = 'Could not download the attachment.';
        });
        return;
      }
      await widget.openDocument(bytes, widget.workerKey);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not open the attachment: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final attached = widget.workerKey.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attached ? 'Attached' : 'Not attached',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (attached && widget.uploader != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _busy ? null : _open,
                    child: Text(_busy ? 'Opening...' : 'Open'),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
          ),
        ],
      ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
