import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> openDocument({
  required Uint8List bytes,
  required String fileName,
  required String contentType,
}) async {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 || dot == fileName.length - 1
      ? ''
      : fileName.substring(dot + 1).toLowerCase();
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}${Platform.pathSeparator}attachment${ext.isEmpty ? '' : '.$ext'}',
  );
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(file.path)]));
}
