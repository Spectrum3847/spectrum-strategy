import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<String> deliverCsv({
  required String csv,
  required String fileName,
}) async {
  final documents = await getApplicationDocumentsDirectory();
  final exportDirectory = Directory(
    '${documents.path}${Platform.pathSeparator}SpectrumStrategy'
    '${Platform.pathSeparator}exports',
  );
  await exportDirectory.create(recursive: true);
  final file = File(
    '${exportDirectory.path}${Platform.pathSeparator}$fileName',
  );
  await file.writeAsBytes(utf8.encode(csv), flush: true);
  await SharePlus.instance.share(
    ShareParams(files: <XFile>[XFile(file.path)], subject: fileName),
  );
  final description = Platform.isAndroid || Platform.isIOS
      ? "the app's exports folder (visible in the Files app on iOS)"
      : 'Documents/SpectrumStrategy/exports';
  return 'Saved $fileName to $description.';
}
