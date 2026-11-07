import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/debug_info.dart';
import 'package:spectrumstrategy/src/ui/about_screen.dart';

const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

DebugInfo _info() => const DebugInfo(
  appVersion: '1.2.3',
  buildNumber: '9',
  platform: 'android',
  osVersion: 'Android 14',
  device: 'Pixel 8',
  gitCommit: 'a1b2c3d',
  gitBranch: 'master',
  buildDate: '',
);

void main() {
  testWidgets('renders app identity, version, and every credit/source link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(debugInfo: Future.value(_info()))),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'About'), findsOneWidget);
    expect(find.text('Spectrum Strategy'), findsOneWidget);
    expect(find.text('Version 1.2.3+9'), findsOneWidget);

    expect(find.text('Made by project516'), findsOneWidget);
    expect(find.text('project516.dev'), findsOneWidget);
    expect(find.text('project516 on GitHub'), findsOneWidget);
    expect(find.text('github.com/Project516'), findsOneWidget);

    expect(find.text('Spectrum 3847'), findsOneWidget);
    expect(find.textContaining('spectrum3847.org'), findsOneWidget);

    expect(find.text('View source on GitHub'), findsOneWidget);
    expect(
      find.text('github.com/Spectrum3847/spectrum-strategy'),
      findsOneWidget,
    );

    expect(find.text('Open source licenses'), findsOneWidget);
  });

  testWidgets('shows a loading placeholder before debug info resolves', (
    tester,
  ) async {
    final completer = Future<DebugInfo>.delayed(
      const Duration(milliseconds: 50),
      _info,
    );
    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(debugInfo: completer)),
    );

    expect(find.text('Loading version...'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Version 1.2.3+9'), findsOneWidget);
  });

  testWidgets('tapping a link that cannot open shows a snack bar', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _urlLauncherChannel,
      (call) async => throw PlatformException(code: 'no_browser'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _urlLauncherChannel,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: AboutScreen(debugInfo: Future.value(_info()))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Made by project516'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
