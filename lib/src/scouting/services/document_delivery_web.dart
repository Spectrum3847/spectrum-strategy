import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> openDocument({
  required Uint8List bytes,
  required String fileName,
  required String contentType,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: contentType),
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
}
