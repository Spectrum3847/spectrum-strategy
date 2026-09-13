import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/services/entry_flags.dart' show stationOfEntry;
import '../scouting/services/scout_field_display.dart';

const Set<ScoutFieldType> redactedExportFieldTypes = <ScoutFieldType>{
  ScoutFieldType.counter,
  ScoutFieldType.multiCounter,
  ScoutFieldType.boolean,
  ScoutFieldType.select,
};

typedef ExportDirResolver =
    Future<({Directory directory, String description})> Function();

class ScoutCsvExport {
  const ScoutCsvExport(this.file, this.locationDescription);

  final File file;
  final String locationDescription;

  String get savedMessage {
    final name = file.path.split(RegExp(r'[\\/]')).last;
    return 'Saved $name to $locationDescription.';
  }
}

class ScoutExportService {
  ScoutExportService({ExportDirResolver? exportDirResolver})
    : _exportDirResolver = exportDirResolver ?? _defaultExportDirResolver;

  final ExportDirResolver _exportDirResolver;

  List<ScoutConfigField> exportFields(ScoutConfig config) => [
    for (final field in config.allFields)
      if (redactedExportFieldTypes.contains(field.type)) field,
  ];

  String buildCsv({
    required ScoutConfig config,
    required List<ScoutEntry> entries,
    required String eventKey,
  }) {
    final fields = exportFields(config);
    final header = <String>[
      'Event',
      'Match',
      'Team',
      'Station',
      'Created (UTC)',
      'Updated (UTC)',
      for (final field in fields) field.title,
    ];

    final buffer = StringBuffer()..writeAll(header.map(_csvCell), ',');
    for (final entry in entries) {
      buffer.write('\r\n');
      final row = <String>[
        eventKey,
        entry.matchId,
        entry.teamNumber.toString(),
        stationOfEntry(entry) ?? '',
        entry.createdAt.toIso8601String(),
        entry.updatedAt.toIso8601String(),
        for (final field in fields)
          displayFieldValue(field, entry.fieldValues[field.code]),
      ];
      buffer.writeAll(row.map(_csvCell), ',');
    }
    return buffer.toString();
  }

  static String _csvCell(String value) {
    final needsQuoting =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuoting) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<ScoutCsvExport> writeCsv({
    required ScoutConfig config,
    required List<ScoutEntry> entries,
    required String eventKey,
  }) async {
    final csv = buildCsv(config: config, entries: entries, eventKey: eventKey);
    final resolved = await _exportDirResolver();
    await resolved.directory.create(recursive: true);
    final file = File(
      '${resolved.directory.path}${Platform.pathSeparator}${_fileName(eventKey)}.csv',
    );
    await file.writeAsBytes(utf8.encode(csv), flush: true);
    return ScoutCsvExport(file, resolved.description);
  }

  Future<ScoutCsvExport> shareCsv({
    required ScoutConfig config,
    required List<ScoutEntry> entries,
    required String eventKey,
  }) async {
    final result = await writeCsv(
      config: config,
      entries: entries,
      eventKey: eventKey,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(result.file.path)],
        subject: '$eventKey scouting export',
      ),
    );
    return result;
  }

  String _fileName(String eventKey) {
    final raw = eventKey
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return raw.isEmpty ? 'scouting_export' : '${raw}_scouting_export';
  }
}

Future<({Directory directory, String description})>
_defaultExportDirResolver() async {
  final directory = await getApplicationDocumentsDirectory();
  final exportDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}SpectrumStrategy'
    '${Platform.pathSeparator}exports',
  );
  return (
    directory: exportDirectory,
    description: Platform.isAndroid || Platform.isIOS
        ? "the app's exports folder (visible in the Files app on iOS)"
        : 'Documents/SpectrumStrategy/exports',
  );
}
