import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/models/strategy_stroke.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_drawing_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

void main() {
  group('ScoutDrawingController', () {
    test('phase selection changes current phase and notifies', () {
      final controller = ScoutDrawingController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.selectedPhase, StrategyPhase.auton);
      controller.selectedPhase = StrategyPhase.teleop;
      expect(controller.selectedPhase, StrategyPhase.teleop);
      expect(notifications, 1);

      controller.selectedPhase = StrategyPhase.teleop;
      expect(notifications, 1);

      controller.dispose();
    });

    test('tool selection changes current tool and notifies', () {
      final controller = ScoutDrawingController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.selectedTool, StrategyTool.draw);
      controller.selectedTool = StrategyTool.delete;
      expect(controller.selectedTool, StrategyTool.delete);
      expect(notifications, 1);

      controller.selectedTool = StrategyTool.delete;
      expect(notifications, 1);

      controller.dispose();
    });

    group('startStroke / extendStroke', () {
      test('startStroke appends a stroke in the selected phase', () {
        final controller = ScoutDrawingController();
        controller.selectedPhase = StrategyPhase.teleop;
        controller.startStroke(const StrategyPoint(0.1, 0.2));

        final strokes = controller.strokesFor(StrategyPhase.teleop);
        expect(strokes.length, 1);
        expect(strokes.single.phase, StrategyPhase.teleop);
        expect(strokes.single.points.length, 1);
        expect(strokes.single.points.single.x, 0.1);
        expect(strokes.single.points.single.y, 0.2);
        expect(controller.isEmpty, isFalse);
        controller.dispose();
      });

      test('extendStroke appends to the last active stroke', () {
        final controller = ScoutDrawingController();
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        controller.extendStroke(const StrategyPoint(0.2, 0.2));
        controller.extendStroke(const StrategyPoint(0.3, 0.3));

        final strokes = controller.strokesFor(StrategyPhase.auton);
        expect(strokes.length, 1);
        expect(strokes.single.points.length, 3);
        controller.dispose();
      });

      test('extendStroke is a no-op when no stroke is active', () {
        final controller = ScoutDrawingController();
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.extendStroke(const StrategyPoint(0.5, 0.5));
        expect(controller.strokesFor(StrategyPhase.auton), isEmpty);
        expect(notifications, 0);
        controller.dispose();
      });

      test('extendStroke skips a duplicate of the last point', () {
        final controller = ScoutDrawingController();
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.extendStroke(const StrategyPoint(0.1, 0.1));
        expect(
          controller.strokesFor(StrategyPhase.auton).single.points.length,
          1,
        );
        expect(notifications, 0);
        controller.dispose();
      });

      test('strokes are isolated per phase', () {
        final controller = ScoutDrawingController();
        controller.selectedPhase = StrategyPhase.auton;
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        controller.selectedPhase = StrategyPhase.endgame;
        controller.startStroke(const StrategyPoint(0.2, 0.2));
        expect(controller.strokesFor(StrategyPhase.auton).length, 1);
        expect(controller.strokesFor(StrategyPhase.endgame).length, 1);
        expect(controller.strokesFor(StrategyPhase.teleop), isEmpty);
        controller.dispose();
      });
    });

    group('eraseAt', () {
      test(
        'removes a stroke whose point is within 24 px on a non-square canvas',
        () {
          const canvasSize = Size(800, 400);
          final controller = ScoutDrawingController();

          controller.startStroke(
            StrategyPoint.fromOffset(const Offset(400, 200), canvasSize),
          );
          expect(controller.strokesFor(StrategyPhase.auton).length, 1);

          final removed = controller.eraseAt(
            const Offset(410, 200),
            canvasSize,
          );
          expect(removed, isTrue);
          expect(controller.strokesFor(StrategyPhase.auton), isEmpty);
          controller.dispose();
        },
      );

      test('does not remove a stroke beyond the 24 px radius on a non-square canvas', () {
        const canvasSize = Size(800, 400);
        final controller = ScoutDrawingController();
        controller.startStroke(
          StrategyPoint.fromOffset(const Offset(400, 200), canvasSize),
        );

        final removed = controller.eraseAt(const Offset(440, 200), canvasSize);
        expect(removed, isFalse);
        expect(controller.strokesFor(StrategyPhase.auton).length, 1);
        controller.dispose();
      });

      test('y-axis hits use the same 24 px radius as x-axis', () {
        const canvasSize = Size(800, 400);
        final controller = ScoutDrawingController();
        controller.startStroke(
          StrategyPoint.fromOffset(const Offset(400, 200), canvasSize),
        );

        final removed = controller.eraseAt(const Offset(400, 220), canvasSize);
        expect(removed, isTrue);
        expect(controller.strokesFor(StrategyPhase.auton), isEmpty);
        controller.dispose();
      });

      test('only erases strokes in the selected phase', () {
        const canvasSize = Size(400, 400);
        final controller = ScoutDrawingController();
        controller.selectedPhase = StrategyPhase.auton;
        controller.startStroke(
          StrategyPoint.fromOffset(const Offset(200, 200), canvasSize),
        );
        controller.selectedPhase = StrategyPhase.teleop;
        controller.startStroke(
          StrategyPoint.fromOffset(const Offset(200, 200), canvasSize),
        );

        final removed = controller.eraseAt(const Offset(200, 200), canvasSize);
        expect(removed, isTrue);
        expect(controller.strokesFor(StrategyPhase.teleop), isEmpty);
        expect(controller.strokesFor(StrategyPhase.auton).length, 1);
        controller.dispose();
      });

      test('returns false when the selected phase has no strokes', () {
        final controller = ScoutDrawingController();
        var notifications = 0;
        controller.addListener(() => notifications++);
        final removed = controller.eraseAt(
          const Offset(10, 10),
          const Size(100, 100),
        );
        expect(removed, isFalse);
        expect(notifications, 0);
        controller.dispose();
      });
    });

    group('toJson / loadFromJson', () {
      test('round-trips strokes by phase', () {
        final controller = ScoutDrawingController();
        controller.selectedPhase = StrategyPhase.auton;
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        controller.extendStroke(const StrategyPoint(0.2, 0.2));
        controller.selectedPhase = StrategyPhase.teleop;
        controller.startStroke(const StrategyPoint(0.3, 0.3));

        final json = controller.toJson();
        expect(json.keys.toSet(), {
          StrategyPhase.auton.name,
          StrategyPhase.teleop.name,
        });

        final reloaded = ScoutDrawingController();
        reloaded.loadFromJson(json);
        expect(reloaded.strokesFor(StrategyPhase.auton).length, 1);
        expect(
          reloaded.strokesFor(StrategyPhase.auton).single.points.length,
          2,
        );
        expect(reloaded.strokesFor(StrategyPhase.teleop).length, 1);
        expect(reloaded.strokesFor(StrategyPhase.endgame), isEmpty);
        expect(reloaded.isEmpty, isFalse);
        controller.dispose();
        reloaded.dispose();
      });

      test('omits empty phases from the serialized output', () {
        final controller = ScoutDrawingController();
        controller.selectedPhase = StrategyPhase.auton;
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        final json = controller.toJson();
        expect(json, contains(StrategyPhase.auton.name));
        expect(json, isNot(contains(StrategyPhase.teleop.name)));
        expect(json, isNot(contains(StrategyPhase.endgame.name)));
        controller.dispose();
      });

      test('loadFromJson(null) clears all phases', () {
        final controller = ScoutDrawingController();
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        expect(controller.isEmpty, isFalse);
        controller.loadFromJson(null);
        expect(controller.isEmpty, isTrue);
        controller.dispose();
      });

      test('loadFromJson ignores an unknown phase key', () {
        final controller = ScoutDrawingController();
        controller.loadFromJson(<String, dynamic>{
          'notAPhase': <Map<String, dynamic>>[
            {
              'phase': 'auton',
              'colorValue': 0,
              'points': <Map<String, dynamic>>[],
            },
          ],
        });
        expect(controller.isEmpty, isTrue);
        controller.dispose();
      });

      test('loadFromJson skips a non-list phase value', () {
        final controller = ScoutDrawingController();
        controller.loadFromJson(<String, dynamic>{
          StrategyPhase.auton.name: 'not a list',
        });
        expect(controller.strokesFor(StrategyPhase.auton), isEmpty);
        controller.dispose();
      });

      test('loadFromJson skips non-map entries, keeps valid strokes', () {
        final controller = ScoutDrawingController();
        controller.loadFromJson(<String, dynamic>{
          StrategyPhase.auton.name: <dynamic>[
            {
              'phase': 'auton',
              'colorValue': 0,
              'points': [
                {'x': 0.1, 'y': 0.2},
              ],
            },
            'corrupt-entry',
            12345,
            null,
            {
              'phase': 'teleop',
              'points': [
                {'x': 0.3, 'y': 0.4},
              ],
            },
          ],
        });
        final strokes = controller.strokesFor(StrategyPhase.auton);

        expect(strokes.length, 2);
        expect(strokes.first.points.single.x, 0.1);
        expect(strokes.last.phase, StrategyPhase.teleop);
        expect(controller.strokesFor(StrategyPhase.endgame), isEmpty);
        controller.dispose();
      });
    });

    group('clear', () {
      test('clears every phase and notifies', () {
        final controller = ScoutDrawingController();
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.selectedPhase = StrategyPhase.auton;
        controller.startStroke(const StrategyPoint(0.1, 0.1));
        controller.selectedPhase = StrategyPhase.teleop;
        controller.startStroke(const StrategyPoint(0.2, 0.2));
        notifications = 0;

        controller.clear();
        expect(controller.isEmpty, isTrue);
        for (final phase in StrategyPhase.values) {
          expect(controller.strokesFor(phase), isEmpty);
        }
        expect(notifications, 1);
        controller.dispose();
      });

      test(
        'strokesFor returns an unmodifiable list and clear empties allStrokes',
        () {
          final controller = ScoutDrawingController();
          controller.startStroke(const StrategyPoint(0.1, 0.1));
          expect(
            () => controller
                .strokesFor(StrategyPhase.auton)
                .add(StrategyStroke(phase: StrategyPhase.auton)),
            throwsUnsupportedError,
          );
          controller.clear();
          for (final phase in StrategyPhase.values) {
            expect(controller.allStrokes[phase], isEmpty);
          }
          controller.dispose();
        },
      );
    });
  });

  group('ScoutEntry.copyWith strokesByPhase', () {
    ScoutEntry entryWithStrokes() => ScoutEntry(
      matchId: 'm1',
      teamNumber: 1,
      strokesByPhase: <String, dynamic>{
        StrategyPhase.auton.name: <Map<String, dynamic>>[
          {
            'phase': 'auton',
            'colorValue': 0,
            'points': <Map<String, dynamic>>[
              {'x': 0.1, 'y': 0.1},
            ],
          },
        ],
      },
    );

    test('omitting strokesByPhase preserves the existing value', () {
      final entry = entryWithStrokes();
      final updated = entry.copyWith(notes: 'updated');
      expect(updated.strokesByPhase, isNotNull);
      expect(updated.strokesByPhase, contains(StrategyPhase.auton.name));
    });

    test('explicit null clears an existing drawing', () {
      final entry = entryWithStrokes();
      expect(entry.strokesByPhase, isNotNull);
      final updated = entry.copyWith(strokesByPhase: null);
      expect(updated.strokesByPhase, isNull);
    });

    test('explicit map replaces the existing drawing', () {
      final entry = entryWithStrokes();
      const replacement = <String, dynamic>{'teleop': <dynamic>[]};
      final updated = entry.copyWith(strokesByPhase: replacement);
      expect(updated.strokesByPhase, replacement);
    });

    test('subsequent null after a previous null stays null', () {
      final entry = entryWithStrokes()
          .copyWith(strokesByPhase: null)
          .copyWith(strokesByPhase: null);
      expect(entry.strokesByPhase, isNull);
    });
  });
}
