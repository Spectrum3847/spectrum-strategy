import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/services/entry_flags.dart' show stationOfEntry;
import '../scouting/services/scout_field_display.dart';
import '../scouting/services/team_summary_stats.dart';
import 'csv_delivery_web.dart'
    if (dart.library.io) 'csv_delivery_io.dart'
    as csv_delivery;

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

  Future<String> shareCsv({
    required ScoutConfig config,
    required List<ScoutEntry> entries,
    required String eventKey,
  }) async {
    final csv = buildCsv(config: config, entries: entries, eventKey: eventKey);
    return csv_delivery.deliverCsv(
      csv: csv,
      fileName: '${_fileName(eventKey)}.csv',
    );
  }

  String buildSummaryCsv({
    required List<TeamSummaryRow> rows,
    required String eventKey,
  }) {
    final header = <String>[
      'Event',
      'Team',
      for (final column in teamSummaryColumns) column.label,
    ];
    final buffer = StringBuffer()..writeAll(header.map(_csvCell), ',');
    for (final row in rows) {
      buffer.write('\r\n');
      final cells = <String>[
        eventKey,
        row.teamNumber.toString(),
        for (final column in teamSummaryColumns)
          _formatSummaryValue(column.getter(row), isRate: column.isRate),
      ];
      buffer.writeAll(cells.map(_csvCell), ',');
    }
    return buffer.toString();
  }

  Future<String> shareSummaryCsv({
    required List<TeamSummaryRow> rows,
    required String eventKey,
  }) async {
    final csv = buildSummaryCsv(rows: rows, eventKey: eventKey);
    return csv_delivery.deliverCsv(
      csv: csv,
      fileName: '${_summaryFileName(eventKey)}.csv',
    );
  }

  static String _formatSummaryValue(double? value, {required bool isRate}) {
    if (value == null) return '';
    if (isRate) return '${(value * 100).round()}%';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  String _summaryFileName(String eventKey) {
    final raw = _slug(eventKey);
    return raw.isEmpty ? 'scouting_summary' : '${raw}_summary';
  }

  String _fileName(String eventKey) {
    final raw = _slug(eventKey);
    return raw.isEmpty ? 'scouting_export' : '${raw}_scouting_export';
  }

  static String _slug(String eventKey) => eventKey
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
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
