import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'document_delivery_web.dart'
    if (dart.library.io) 'document_delivery_io.dart'
    as document_delivery;

const Map<String, String> documentContentTypesByExtension = <String, String>{
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
};

class PickedDocument {
  const PickedDocument({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

Future<PickedDocument?> pickDocumentFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: documentContentTypesByExtension.keys.toList(
      growable: false,
    ),
  );
  if (result.isEmpty) return null;
  final file = result.first;
  final ext = _extensionOf(file.name);
  final contentType = documentContentTypesByExtension[ext];
  if (contentType == null) return null;
  return PickedDocument(
    bytes: await file.readAsBytes(),
    contentType: contentType,
  );
}

String contentTypeForKey(String workerKey) =>
    documentContentTypesByExtension[_extensionOf(workerKey)] ??
    'application/octet-stream';

Future<void> openDocumentBytes(Uint8List bytes, String workerKey) async {
  await document_delivery.openDocument(
    bytes: bytes,
    fileName: workerKey,
    contentType: contentTypeForKey(workerKey),
  );
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}
