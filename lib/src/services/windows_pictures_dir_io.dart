import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String? windowsPicturesPath() {
  if (!Platform.isWindows) return null;

  final rfid = calloc<GUID>();
  rfid.ref
    ..Data1 = FOLDERID_Pictures.Data1
    ..Data2 = FOLDERID_Pictures.Data2
    ..Data3 = FOLDERID_Pictures.Data3
    ..Data4 = FOLDERID_Pictures.Data4;
  try {
    final path = SHGetKnownFolderPath(rfid, KF_FLAG_DEFAULT, null);
    try {
      final resolved = path.toDartString();
      return resolved.isEmpty ? null : resolved;
    } finally {
      CoTaskMemFree(path.cast());
    }
  } catch (_) {
    return null;
  } finally {
    calloc.free(rfid);
  }
}
