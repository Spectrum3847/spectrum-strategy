import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'windows_pictures_dir.dart';

Future<String> savePng({
  required Uint8List bytes,
  required String fileName,
  Future<({String directoryPath, String description})> Function()?
  exportDirResolver,
}) async {
  final resolved = await (exportDirResolver ?? _defaultExportDirResolver)();
  final directory = Directory(resolved.directoryPath);
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return 'Saved $fileName to ${resolved.description}.';
}

Future<String> sharePng({
  required Uint8List bytes,
  required String fileName,
  required String subject,
  Future<({String directoryPath, String description})> Function()?
  exportDirResolver,
}) async {
  final resolved = await (exportDirResolver ?? _defaultExportDirResolver)();
  final directory = Directory(resolved.directoryPath);
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: <XFile>[XFile(file.path)], subject: subject),
  );
  return 'Shared $subject.';
}

String _homeDirectory() {
  if (!Platform.isWindows) return Platform.environment['HOME'] ?? '';
  return Platform.environment['USERPROFILE'] ??
      ((Platform.environment['HOMEDRIVE'] ?? '') +
          (Platform.environment['HOMEPATH'] ?? ''));
}

Future<({String directoryPath, String description})>
_defaultExportDirResolver() async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final resolved = windowsPicturesPath();
    final path = resolved != null
        ? '$resolved${Platform.pathSeparator}SpectrumStrategy'
        : '${_homeDirectory()}${Platform.pathSeparator}Pictures'
              '${Platform.pathSeparator}SpectrumStrategy';
    return (directoryPath: path, description: 'Pictures/SpectrumStrategy');
  }
  final directory = await getApplicationDocumentsDirectory();
  final exportPath = '${directory.path}${Platform.pathSeparator}exports';
  return (
    directoryPath: exportPath,
    description: "the app's exports folder (visible in the Files app on iOS)",
  );
}
