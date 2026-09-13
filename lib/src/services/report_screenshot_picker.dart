import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:image_picker/image_picker.dart';

import '../scouting/services/pit_photo_capture.dart' show compressPhotoBytes;

const int maxReportScreenshots = 3;

const int maxReportScreenshotBytes = 2 * 1024 * 1024;

class PickedScreenshot {
  const PickedScreenshot({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

class ScreenshotPickException implements Exception {
  const ScreenshotPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

Future<PickedScreenshot?> pickReportScreenshot({
  ImagePicker? imagePicker,
  Future<List<PlatformFile>> Function()? filePicker,
}) async {
  if (_isMobile) {
    final picked = await (imagePicker ?? ImagePicker()).pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final bytes = await compressPhotoBytes(await picked.readAsBytes());
    return _checked(bytes, 'image/jpeg');
  }

  final result =
      await (filePicker ??
          () => FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: _imageExtensions,
          ))();
  if (result.isEmpty) return null;
  final file = result.first;
  return _checked(await file.readAsBytes(), _contentTypeFor(file.name));
}

PickedScreenshot _checked(Uint8List bytes, String contentType) {
  if (bytes.isEmpty) {
    throw const ScreenshotPickException('That image is empty.');
  }
  if (bytes.length > maxReportScreenshotBytes) {
    throw const ScreenshotPickException(
      'That image is over the 2 MB limit. Crop or shrink it and try again.',
    );
  }
  return PickedScreenshot(bytes: bytes, contentType: contentType);
}

const List<String> _imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic'];

String _contentTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    default:
      throw const ScreenshotPickException(
        'Pick a JPG, PNG, WebP or HEIC image.',
      );
  }
}
