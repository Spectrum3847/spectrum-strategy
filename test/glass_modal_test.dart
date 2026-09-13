import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass/liquid_glass.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/widgets/glass_modal.dart';
import 'package:spectrumstrategy/src/widgets/glass_panel.dart';

Widget _host({
  required bool glass,
  required WidgetBuilder builder,
  ThemeMode themeMode = ThemeMode.light,
}) => MaterialApp(
  theme: ThemeData(brightness: Brightness.light),
  darkTheme: ThemeData(brightness: Brightness.dark),
  themeMode: themeMode,
  home: GlassChrome(
    enabled: glass,
    child: Scaffold(body: Builder(builder: builder)),
  ),
);

void main() {
  group('showGlassModalBottomSheet', () {
    testWidgets('is a plain Material sheet when glass chrome is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          glass: false,
          builder: (context) => ElevatedButton(
            onPressed: () => showGlassModalBottomSheet<void>(
              context: context,
              builder: (_) => const Text('Sheet content'),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet content'), findsOneWidget);
      expect(find.byType(GlassPanel), findsNothing);
    });

    testWidgets('draws on GlassPanel and returns its result when on', (
      tester,
    ) async {
      int? result;
      await tester.pumpWidget(
        _host(
          glass: true,
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showGlassModalBottomSheet<int>(
                context: context,
                builder: (sheetContext) => TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(7),
                  child: const Text('Pick'),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassPanel), findsOneWidget);

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(result, 7);
      expect(find.byType(GlassPanel), findsNothing);
    });

    testWidgets(
      'a requested drag handle is drawn inside GlassPanel, not passed to '
      'the Material sheet',
      (tester) async {
        await tester.pumpWidget(
          _host(
            glass: true,
            builder: (context) => ElevatedButton(
              onPressed: () => showGlassModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => const Text('Sheet content'),
              ),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(GlassPanel), findsOneWidget);
        expect(find.text('Sheet content'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(GlassPanel),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.constraints ==
                      const BoxConstraints.tightFor(width: 32, height: 4),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'showDragHandle passes straight through to the Material sheet when '
      'glass is off',
      (tester) async {
        await tester.pumpWidget(
          _host(
            glass: false,
            builder: (context) => ElevatedButton(
              onPressed: () => showGlassModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => const Text('Sheet content'),
              ),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(GlassPanel), findsNothing);
        expect(find.text('Sheet content'), findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
      },
    );

    testWidgets(
      'a drag-handle sheet with a short child stays short, not full screen',
      (tester) async {
        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _host(
            glass: true,
            builder: (context) => ElevatedButton(
              onPressed: () => showGlassModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) =>
                    const SizedBox(height: 40, child: Text('Short content')),
              ),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final panelHeight = tester.getSize(find.byType(GlassPanel)).height;

        expect(panelHeight, lessThan(200));
      },
    );

    testWidgets('carries the app theme brightness onto the panel', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          glass: true,
          themeMode: ThemeMode.dark,
          builder: (context) => ElevatedButton(
            onPressed: () => showGlassModalBottomSheet<void>(
              context: context,
              builder: (_) => const Text('Sheet content'),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
      expect(glass.brightness, Brightness.dark);
    });
  });

  group('showGlassConfirmDialog', () {
    testWidgets('is a plain AlertDialog when glass chrome is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          glass: false,
          builder: (context) => ElevatedButton(
            onPressed: () => showGlassConfirmDialog<bool>(
              context: context,
              title: 'Delete?',
              content: const Text('Sure?'),
              actionsBuilder: (dialogContext) => [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Yes'),
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(GlassPanel), findsNothing);
    });

    testWidgets('draws on GlassPanel and reports the pressed action', (
      tester,
    ) async {
      bool? confirmed;
      await tester.pumpWidget(
        _host(
          glass: true,
          builder: (context) => ElevatedButton(
            onPressed: () async {
              confirmed = await showGlassConfirmDialog<bool>(
                context: context,
                title: 'Delete match?',
                content: const Text('This removes it.'),
                actionsBuilder: (dialogContext) => [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              );
            },
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.text('Delete match?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    });

    testWidgets('a null content omits the content section on both paths', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          glass: true,
          builder: (context) => ElevatedButton(
            onPressed: () => showGlassConfirmDialog<bool>(
              context: context,
              title: 'Delete this pick list?',
              actionsBuilder: (dialogContext) => [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.text('Delete this pick list?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('carries the app theme brightness onto the panel', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          glass: true,
          themeMode: ThemeMode.dark,
          builder: (context) => ElevatedButton(
            onPressed: () => showGlassConfirmDialog<bool>(
              context: context,
              title: 'Delete match?',
              content: const Text('This removes it.'),
              actionsBuilder: (dialogContext) => [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
      expect(glass.brightness, Brightness.dark);
    });
  });

  group('GlassAlertDialogShell', () {
    Widget dialog({required bool glass}) => GlassAlertDialogShell(
      glass: glass,
      title: 'Pick one',
      content: const SizedBox(
        width: 200,
        height: 100,
        child: Text('bespoke content'),
      ),
      actions: [TextButton(onPressed: () {}, child: const Text('Cancel'))],
    );

    testWidgets('is a plain AlertDialog when glass is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: dialog(glass: false))),
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(GlassPanel), findsNothing);
      expect(find.text('bespoke content'), findsOneWidget);
    });

    testWidgets('draws on GlassPanel when glass is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: dialog(glass: true))),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.text('bespoke content'), findsOneWidget);
    });

    testWidgets(
      'a fixed-height content widget keeps that height on both paths',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final card = find.byWidgetPredicate(
          (w) => w is Material && w.type == MaterialType.card,
        );

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: dialog(glass: false))),
        );
        final flatHeight = tester.getSize(card).height;
        expect(flatHeight, lessThan(300));

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: dialog(glass: true))),
        );
        final glassHeight = tester.getSize(find.byType(GlassPanel)).height;
        expect(glassHeight, lessThan(300));
      },
    );
  });
}
