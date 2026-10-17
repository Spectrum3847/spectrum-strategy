import 'dart:typed_data';

class WebPickedFile {
  const WebPickedFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

Future<WebPickedFile?> pickImageViaWebInput(List<String> extensions) =>
    throw UnsupportedError('pickImageViaWebInput is web-only');
