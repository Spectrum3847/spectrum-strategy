import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/widgets/strategy_field_canvas.dart';
import 'package:spectrumstrategy/src/widgets/strategy_legend_painter.dart';

import 'support/fake_match_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legend strokes round trip, undo, and erase independently of the field',
    () async {
      final controller = StrategyController(directory: FakeMatchDirectory());
      await controller.bootstrap();
      addTearDown(controller.dispose);
      void draw({bool legend = false}) {
        controller.selectTool(StrategyTool.draw);
        controller.startStroke(const StrategyPoint(0.5, 0.5), isLegend: legend);
        controller.extendStroke(const StrategyPoint(0.6, 0.5));
        controller.finishStroke();
      }

      draw();
      draw(legend: true);
      final restored = StrategySession.fromJson(controller.session.toJson());
      expect(restored.strokesFor(StrategyPhase.auton).map((s) => s.isLegend), [
        false,
        true,
      ]);
      controller.undo();
      expect(
        controller.session.strokesFor(StrategyPhase.auton).single.isLegend,
        isFalse,
      );
      controller.redo();
      controller.selectTool(StrategyTool.delete);
      expect(
        controller.eraseAt(
          const Offset(50, 50),
          const Size(100, 100),
          isLegend: true,
        ),
        isTrue,
      );
      controller.finishErase();
      expect(
        controller.session.strokesFor(StrategyPhase.auton).single.isLegend,
        isFalse,
      );
      controller.undo();
      expect(
        controller.eraseAt(const Offset(50, 50), const Size(100, 100)),
        isTrue,
      );
      controller.finishErase();
      expect(
        controller.session.strokesFor(StrategyPhase.auton).single.isLegend,
        isTrue,
      );
      controller.selectPhase(StrategyPhase.teleop);
      expect(controller.session.strokesFor(StrategyPhase.teleop), isEmpty);
      controller.selectPhase(StrategyPhase.auton);
      controller.clearSelectedPhase();
      expect(controller.session.strokesFor(StrategyPhase.auton), isEmpty);
      controller.undo();
      expect(
        controller.session.strokesFor(StrategyPhase.auton).single.isLegend,
        isTrue,
      );
      await controller.saveNow();
    },
  );

  test('old strokes without a legend flag stay on the field', () {
    final session = StrategySession.fromJson({
      'strokesByPhase': {
        'auton': [
          {'phase': 'auton', 'points': <Object>[]},
        ],
      },
    });
    expect(session.strokesFor(StrategyPhase.auton).single.isLegend, isFalse);
  });

  testWidgets(
    'legend accepts handwriting, ignores a second pointer, and exports with the field',
    (tester) async {
      final controller = StrategyController(directory: FakeMatchDirectory());
      await controller.bootstrap();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 364,
                child: StrategyFieldCanvas(
                  controller: controller,
                  repaintKey: boundary,
                  fieldAspectRatio: 2,
                  showLegend: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final legend = find.byKey(const ValueKey('strategy-team-legend'));
      expect(legend, findsOneWidget);
      expect(
        find.descendant(of: find.byKey(boundary), matching: legend),
        findsOneWidget,
      );
      final start = tester.getTopLeft(legend) + const Offset(60, 20);
      final pen = await tester.startGesture(start);
      await pen.moveBy(const Offset(10, 20));
      final palm = await tester.startGesture(
        start + const Offset(200, 0),
        pointer: 2,
      );
      await palm.moveBy(const Offset(30, 0));
      await pen.up();
      await palm.up();
      await tester.pump();
      final strokes = controller.session.strokesFor(StrategyPhase.auton);
      expect(strokes, hasLength(1));
      expect(strokes.single.isLegend, isTrue);
      expect(strokes.single.points, hasLength(2));
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is StrategyLegendPainter,
        ),
        findsOneWidget,
      );
      controller.selectTool(StrategyTool.delete);
      await tester.tapAt(start);
      await tester.pump();
      expect(controller.session.strokesFor(StrategyPhase.auton), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pumpAndSettle();
    },
  );
}
