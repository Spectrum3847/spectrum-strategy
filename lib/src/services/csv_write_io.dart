import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'scout_csv_export.dart';

Future<ScoutCsvExport> writeCsvFile({
  required String csv,
  required String fileName,
  ExportDirResolver? exportDirResolver,
}) async {
  final resolved = await (exportDirResolver ?? _defaultExportDirResolver)();
  final directory = Directory(resolved.directory);
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(utf8.encode(csv), flush: true);
  return ScoutCsvExport(file.path, resolved.description);
}

Future<({String directory, String description})>
_defaultExportDirResolver() async {
  final documents = await getApplicationDocumentsDirectory();
  final exportDirectory =
      '${documents.path}${Platform.pathSeparator}SpectrumStrategy'
      '${Platform.pathSeparator}exports';
  return (
    directory: exportDirectory,
    description: Platform.isAndroid || Platform.isIOS
        ? "the app's exports folder (visible in the Files app on iOS)"
        : 'Documents/SpectrumStrategy/exports',
  );
}
