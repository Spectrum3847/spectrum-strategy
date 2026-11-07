library;

import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'pit_photo_store.dart';

const int _maxEdge = 1280;

const int _jpegQuality = 80;

void validatePhotoPathSegment(String segment) {
  if (segment.isEmpty ||
      segment.contains('/') ||
      segment.contains('\\') ||
      segment.contains('..') ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment)) {
    throw ArgumentError('Invalid path segment: $segment');
  }
}

Future<Uint8List> pickAndCompressPhoto(PhotoSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: _maxEdge.toDouble(),
    imageQuality: _jpegQuality,
  );
  if (picked == null) {
    throw StateError('No image selected');
  }
  return compressPhotoBytes(await picked.readAsBytes());
}

Future<Uint8List> compressPhotoBytes(Uint8List bytes) async {
  try {
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: _maxEdge,
      minHeight: _maxEdge,
      quality: _jpegQuality,
      format: CompressFormat.jpeg,
    );
    return compressed.isEmpty ? bytes : compressed;
  } catch (_) {
    return bytes;
  }
}
