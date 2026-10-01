import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/windows_pictures_dir.dart';

void main() {
  test('the lookup is inert off Windows', () {
    if (Platform.isWindows) {
      final path = windowsPicturesPath();
      expect(path, anyOf(isNull, isNotEmpty));
      return;
    }
    expect(windowsPicturesPath(), isNull);
  });

  test('calling it repeatedly is safe', () {
    for (var i = 0; i < 50; i++) {
      windowsPicturesPath();
    }
  });
}
