import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const minHeight = 48.0;

  Future<Size> buttonSize(
    WidgetTester tester,
    ThemeData theme,
    Widget button,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: button)),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(button.runtimeType));
  }

  for (final (name, themeBuilder) in <(String, ThemeData Function())>[
    ('light', buildAppTheme),
    ('dark', buildDarkAppTheme),
  ]) {
    group('$name theme', () {
      testWidgets('a filled button clears the minimum target', (tester) async {
        final size = await buttonSize(
          tester,
          themeBuilder(),
          FilledButton(onPressed: () {}, child: const Text('Go')),
        );
        expect(size.height, greaterThanOrEqualTo(minHeight));
      });

      testWidgets('an outlined button clears it', (tester) async {
        final size = await buttonSize(
          tester,
          themeBuilder(),
          OutlinedButton(onPressed: () {}, child: const Text('Go')),
        );
        expect(size.height, greaterThanOrEqualTo(minHeight));
      });

      testWidgets('a text button clears it too', (tester) async {
        final size = await buttonSize(
          tester,
          themeBuilder(),
          TextButton(onPressed: () {}, child: const Text('Go')),
        );
        expect(size.height, greaterThanOrEqualTo(minHeight));
      });

      testWidgets('a short label still clears the minimum width', (
        tester,
      ) async {
        final size = await buttonSize(
          tester,
          themeBuilder(),
          FilledButton(onPressed: () {}, child: const Text('x')),
        );
        expect(size.width, greaterThanOrEqualTo(64.0));
      });
    });
  }
}
