import 'dart:js_interop';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

Future<String> savePng({
  required Uint8List bytes,
  required String fileName,
  Future<({String directoryPath, String description})> Function()?
  exportDirResolver,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();

  Future<void>.delayed(const Duration(seconds: 30), () {
    anchor.remove();
    web.URL.revokeObjectURL(url);
  });
  return 'Downloaded $fileName.';
}

Future<String> sharePng({
  required Uint8List bytes,
  required String fileName,
  required String subject,
  Future<({String directoryPath, String description})> Function()?
  exportDirResolver,
}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(bytes, name: fileName, mimeType: 'image/png'),
        ],
        subject: subject,
        downloadFallbackEnabled: false,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.unavailable => await savePng(
        bytes: bytes,
        fileName: fileName,
      ),
      ShareResultStatus.dismissed => '',
      ShareResultStatus.success => 'Shared $subject.',
    };
  } catch (_) {
    return savePng(bytes: bytes, fileName: fileName);
  }
}
