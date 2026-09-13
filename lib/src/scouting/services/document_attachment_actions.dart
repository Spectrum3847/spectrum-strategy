import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

Future<void> openDocumentBytes(Uint8List bytes, String workerKey) async {
  final ext = _extensionOf(workerKey);
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}${Platform.pathSeparator}attachment${ext.isEmpty ? '' : '.$ext'}',
  );
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(file.path)]));
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}
