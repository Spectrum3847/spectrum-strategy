import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass/liquid_glass.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/widgets/glass_popup_menu.dart';

Widget _host({
  required bool glass,
  required Widget button,
  ThemeMode themeMode = ThemeMode.light,
}) => MaterialApp(
  theme: ThemeData(brightness: Brightness.light),
  darkTheme: ThemeData(brightness: Brightness.dark),
  themeMode: themeMode,
  home: GlassChrome(
    enabled: glass,
    child: Scaffold(
      appBar: AppBar(title: const Text('t'), actions: [button]),
      body: const SizedBox.expand(),
    ),
  ),
);

List<PopupMenuEntry<String>> _items(BuildContext _) => const [
  PopupMenuItem<String>(value: 'a', child: Text('Alpha')),
  PopupMenuDivider(),
  PopupMenuItem<String>(value: 'b', child: Text('Beta')),
];

void main() {
  testWidgets('is a plain Material menu when glass chrome is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        glass: false,
        button: GlassPopupMenuButton<String>(
          tooltip: 'More',
          itemBuilder: _items,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });

  testWidgets('with glass on it opens its own route and reports the pick', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        glass: true,
        button: GlassPopupMenuButton<String>(
          tooltip: 'More',
          itemBuilder: _items,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    final button = tester.getRect(find.byTooltip('More'));
    final menu = tester.getRect(find.text('Beta'));
    expect(menu.top, greaterThan(button.bottom));
    expect(menu.right, lessThanOrEqualTo(button.right));

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('tapping outside a glass menu cancels it', (tester) async {
    String? picked;
    var canceled = false;
    await tester.pumpWidget(
      _host(
        glass: true,
        button: GlassPopupMenuButton<String>(
          tooltip: 'More',
          itemBuilder: _items,
          onSelected: (v) => picked = v,
          onCanceled: () => canceled = true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(picked, isNull);
    expect(canceled, isTrue);
  });

  testWidgets('a child button keeps its tooltip and opens the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        glass: true,
        button: GlassPopupMenuButton<String>(
          tooltip: 'Row order',
          itemBuilder: _items,
          initialValue: 'a',
          child: const Text('Order'),
        ),
      ),
    );
    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byTooltip('Row order'), findsOneWidget);
  });

  testWidgets(
    'the glass panel carries the app theme brightness, not the system default',
    (tester) async {
      await tester.pumpWidget(
        _host(
          glass: true,
          themeMode: ThemeMode.dark,
          button: GlassPopupMenuButton<String>(
            tooltip: 'More',
            itemBuilder: _items,
            onSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
      expect(glass.brightness, Brightness.dark);
    },
  );
}
