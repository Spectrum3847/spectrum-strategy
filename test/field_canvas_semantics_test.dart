import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/widgets/field_canvas_semantics.dart';

void main() {
  test('an empty surface says so, rather than listing nothing', () {
    expect(
      fieldCanvasLabel(
        surface: 'Strategy board',
        phase: StrategyPhase.auton,
        strokeCount: 0,
      ),
      'Strategy board, Auton phase, empty',
    );
  });

  test('the label carries what is on the surface', () {
    expect(
      fieldCanvasLabel(
        surface: 'Strategy board',
        phase: StrategyPhase.teleop,
        strokeCount: 3,
        markerCount: 6,
      ),
      'Strategy board, Teleop phase, 3 drawings, 6 robots',
    );
  });

  test('one of a thing is singular', () {
    expect(
      fieldCanvasLabel(
        surface: 'Strategy board',
        phase: StrategyPhase.endgame,
        strokeCount: 1,
        markerCount: 1,
      ),
      'Strategy board, Endgame phase, 1 drawing, 1 robot',
    );
  });

  test('a count of zero is left out rather than announced', () {
    expect(
      fieldCanvasLabel(
        surface: 'Scouting drawing',
        phase: StrategyPhase.auton,
        strokeCount: 2,
      ),
      'Scouting drawing, Auton phase, 2 drawings',
    );
  });

  test('a read-only surface says it cannot be drawn on', () {
    expect(
      fieldCanvasLabel(
        surface: 'Scouting drawing',
        phase: StrategyPhase.auton,
        strokeCount: 0,
        readOnly: true,
      ),
      'Scouting drawing, Auton phase, empty, read only',
    );
  });
}
