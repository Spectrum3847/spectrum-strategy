import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/desktop_tray_service_io.dart';

void main() {
  test('quit flushes pending saves before destroying the window', () async {
    final calls = <String>[];
    final service = DesktopTrayService(
      destroyWindow: () async => calls.add('destroy'),
      exitProcess: (_) => calls.add('exit'),
    )..flushBeforeQuit = () async => calls.add('flush');

    await service.quit();

    expect(calls, ['flush', 'destroy', 'exit']);
  });

  test('a flush that never finishes does not block quit', () async {
    final calls = <String>[];
    final service = DesktopTrayService(
      destroyWindow: () async => calls.add('destroy'),
      exitProcess: (_) => calls.add('exit'),
    )..flushBeforeQuit = () => Completer<void>().future;

    await service.quit();

    expect(calls, ['destroy', 'exit']);
  });

  test('a failing flush does not block quit', () async {
    final calls = <String>[];
    final service = DesktopTrayService(
      destroyWindow: () async => calls.add('destroy'),
      exitProcess: (_) => calls.add('exit'),
    )..flushBeforeQuit = () async => throw StateError('disk full');

    await service.quit();

    expect(calls, ['destroy', 'exit']);
  });
}
