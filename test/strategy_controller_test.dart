import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart' show AppLifecycleState, HSLColor;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/robot_marker.dart';
import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/models/strategy_stroke.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';
import 'package:spectrumstrategy/src/services/team_loader.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_strategy_board_sync_service.dart';
import 'support/laggy_match_directory.dart';

class _FlakyMatchDirectory extends FakeMatchDirectory {
  bool failNextSave = false;
  bool failNextActiveIdRead = false;

  @override
  Future<void> saveMatch(StrategySession session) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('simulated storage failure');
    }
    await super.saveMatch(session);
  }

  @override
  Future<String?> getActiveMatchId() async {
    if (failNextActiveIdRead) {
      failNextActiveIdRead = false;
      throw StateError('simulated storage failure');
    }
    return super.getActiveMatchId();
  }
}

void main() {
  test('TeamLoader parses and deduplicates numbers', () {
    final teams = TeamLoader.parseTeamNumbers('3847, 2714\n5114 3847\t987');
    expect(teams, <int>[987, 2714, 3847, 5114]);
  });

  test('TeamLoader drops overflowing and out-of-range numbers', () {
    final teams = TeamLoader.parseTeamNumbers('3847 ${'9' * 25} 0 100000 254');
    expect(teams, <int>[254, 3847]);
  });

  test('StrategyController records drawing and robot placement', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.loadTeamsFromText('3847, 2714');
    controller.selectPhase(StrategyPhase.teleop);
    controller.setSelectedRobotTeam(3847);
    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();
    controller.selectTool(StrategyTool.robot);
    controller.placeRobot(const StrategyPoint(0.5, 0.6));

    expect(controller.session.teamNumbers, <int>[2714, 3847]);
    expect(controller.session.strokesFor(StrategyPhase.teleop), hasLength(1));
    expect(
      controller.session.strokesFor(StrategyPhase.teleop).first.colorValue,
      StrategyPalette.auton.toARGB32(),
    );
    expect(controller.session.markersFor(StrategyPhase.teleop), hasLength(1));
    final marker = controller.session.markersFor(StrategyPhase.teleop).first;
    expect(marker.teamNumber, 3847);
    expect(marker.alliance, controller.session.alliance);
    expect(controller.session.selectedFieldId, kLatestFieldId);
  });

  test('the selected tool survives a phase switch', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.selectTool(StrategyTool.delete);
    controller.selectPhase(StrategyPhase.teleop);
    expect(controller.session.selectedTool, StrategyTool.delete);
    controller.selectPhase(StrategyPhase.endgame);
    expect(controller.session.selectedTool, StrategyTool.delete);

    controller.selectTool(StrategyTool.robot);
    controller.selectPhase(StrategyPhase.auton);
    expect(controller.session.selectedTool, StrategyTool.robot);
  });

  test('every stroke starts from the same base purple', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();
    controller.selectTool(StrategyTool.draw);

    final base = StrategyPalette.auton.toARGB32();
    for (final phase in StrategyPhase.values) {
      controller.selectPhase(phase);
      for (var i = 0; i < 4; i++) {
        controller.startStroke(StrategyPoint(0.1 + i * 0.05, 0.1));
        controller.extendStroke(StrategyPoint(0.2 + i * 0.05, 0.2));
        controller.finishStroke();
      }
      for (final stroke in controller.session.strokesFor(phase)) {
        expect(stroke.colorValue, base);
      }
    }
  });

  test('the base purple stays dark enough to read as a start', () async {
    final lightness = HSLColor.fromColor(StrategyPalette.auton).lightness;
    expect(lightness, lessThan(0.35));
  });

  test('StrategySession.fromJson defaults selectedFieldId to latest', () {
    final session = StrategySession.fromJson(<String, dynamic>{
      'id': 'abc',
      'selectedPhase': StrategyPhase.auton.name,
      'selectedTool': StrategyTool.draw.name,
      'strokesByPhase': <String, dynamic>{},
      'markersByPhase': <String, dynamic>{},
      'notesByPhase': <String, dynamic>{},
    });
    expect(session.selectedFieldId, kLatestFieldId);
  });

  test(
    'new sessions use the latest field id resolved from the manifest loader',
    () async {
      var loaderCalls = 0;
      final controller = StrategyController(
        directory: FakeMatchDirectory(),
        latestFieldIdLoader: () async {
          loaderCalls++;
          return '2027-rebuilt';
        },
      );
      await controller.bootstrap();

      expect(controller.session.selectedFieldId, '2027-rebuilt');
      final created = await controller.createMatch(matchNumber: 2);
      expect(created.selectedFieldId, '2027-rebuilt');

      expect(loaderCalls, 1);
    },
  );

  test(
    'field id falls back to kLatestFieldId when the loader throws',
    () async {
      final controller = StrategyController(
        directory: FakeMatchDirectory(),
        latestFieldIdLoader: () async => throw StateError('no manifest'),
      );
      await controller.bootstrap();
      expect(controller.session.selectedFieldId, kLatestFieldId);
    },
  );

  test('StrategyController persists selected field id', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();
    controller.selectField('2025-reefscape');
    await controller.saveNow();

    final round = StrategySession.fromJson(controller.session.toJson());
    expect(round.selectedFieldId, '2025-reefscape');
  });

  test('robot tool drags an existing marker instead of stacking one', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();
    controller.selectTool(StrategyTool.robot);
    const size = Size(400, 200);

    controller.placeRobot(const StrategyPoint(0.5, 0.5));
    controller.finishMarkerDrag();
    final phase = controller.session.selectedPhase;
    expect(controller.session.markersFor(phase), hasLength(1));

    expect(controller.startMarkerDragAt(const Offset(200, 100), size), isTrue);
    controller.updateMarkerDrag(const StrategyPoint(0.25, 0.25));
    controller.finishMarkerDrag();
    final markers = controller.session.markersFor(phase);
    expect(markers, hasLength(1));
    expect(markers.single.position.x, 0.25);
    expect(markers.single.position.y, 0.25);

    expect(controller.startMarkerDragAt(const Offset(390, 10), size), isFalse);
  });

  test('a freshly placed marker follows the same gesture', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();
    controller.selectTool(StrategyTool.robot);

    controller.placeRobot(const StrategyPoint(0.5, 0.5));
    controller.updateMarkerDrag(const StrategyPoint(0.6, 0.7));
    controller.finishMarkerDrag();

    final phase = controller.session.selectedPhase;
    final markers = controller.session.markersFor(phase);
    expect(markers, hasLength(1));
    expect(markers.single.position.x, 0.6);
    expect(markers.single.position.y, 0.7);
  });

  test(
    'placeRobot will not put the same team on the field twice in a phase',
    () async {
      final controller = StrategyController(directory: FakeMatchDirectory());
      await controller.bootstrap();
      controller.loadTeamsFromText('3847, 2714');
      controller.selectPhase(StrategyPhase.teleop);
      controller.selectTool(StrategyTool.robot);

      controller.setSelectedRobotTeam(3847);
      controller.placeRobot(const StrategyPoint(0.2, 0.2));

      expect(controller.session.selectedRobotTeam, 2714);
      expect(controller.teamsPlacedInPhase(StrategyPhase.teleop), {3847});
      expect(controller.teamsAvailableInPhase(StrategyPhase.teleop), [2714]);

      controller.setSelectedRobotTeam(3847);
      controller.placeRobot(const StrategyPoint(0.5, 0.5));
      expect(controller.session.markersFor(StrategyPhase.teleop), hasLength(1));

      controller.selectPhase(StrategyPhase.endgame);
      controller.selectTool(StrategyTool.robot);
      controller.setSelectedRobotTeam(3847);
      controller.placeRobot(const StrategyPoint(0.3, 0.3));
      expect(
        controller.session.markersFor(StrategyPhase.endgame),
        hasLength(1),
      );
    },
  );

  test('RobotMarker preserves alliance through json round-trip', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();
    controller.setAlliance('Blue');
    controller.selectTool(StrategyTool.robot);
    controller.placeRobot(const StrategyPoint(0.3, 0.4));
    await controller.saveNow();

    final json = controller.session.toJson();
    final round = StrategySession.fromJson(json);
    expect(
      round.markersFor(controller.session.selectedPhase).first.alliance,
      'Blue',
    );
  });

  test('RobotMarker.fromJson defaults to Red alliance for legacy data', () {
    final marker = RobotMarker.fromJson(<String, dynamic>{
      'phase': StrategyPhase.auton.name,
      'position': const StrategyPoint(0.5, 0.5).toJson(),
      'teamNumber': 3847,
      'label': null,
    });
    expect(marker.alliance, 'Red');
  });

  test('StrategyController keeps clears ahead of pending saves', () async {
    final directory = LaggyMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();

    final initialSaveCount = directory.savedSessions.length;
    directory.firstSaveGate = Completer<void>();

    controller.selectPhase(StrategyPhase.teleop);
    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();

    final firstSave = controller.saveNow();
    await Future<void>.delayed(Duration.zero);

    controller.clearSelectedPhase();
    final secondSave = controller.saveNow();
    await Future<void>.delayed(Duration.zero);

    expect(directory.savedSessions, hasLength(initialSaveCount + 1));
    expect(
      directory.savedSessions.last.strokesFor(StrategyPhase.teleop),
      hasLength(1),
    );

    directory.firstSaveGate!.complete();

    await firstSave;
    await secondSave;

    expect(
      directory.savedSessions.last.strokesFor(StrategyPhase.teleop),
      isEmpty,
    );
  });

  test('StrategyController preserves drawing content on bootstrap', () async {
    final directory = FakeMatchDirectory();
    final preloaded = StrategyController(directory: directory);
    await preloaded.bootstrap();

    preloaded.selectPhase(StrategyPhase.teleop);
    preloaded.setSelectedRobotTeam(3847);
    preloaded.selectTool(StrategyTool.draw);
    preloaded.startStroke(const StrategyPoint(0.1, 0.2));
    preloaded.extendStroke(const StrategyPoint(0.2, 0.3));
    preloaded.finishStroke();
    preloaded.selectTool(StrategyTool.robot);
    preloaded.placeRobot(const StrategyPoint(0.4, 0.5));
    preloaded.updateNote('hold left side');
    await preloaded.saveNow();

    final relaunched = StrategyController(directory: directory);
    await relaunched.bootstrap();

    expect(relaunched.session.id, preloaded.session.id);
    expect(relaunched.session.strokesFor(StrategyPhase.teleop), hasLength(1));
    expect(relaunched.session.markersFor(StrategyPhase.teleop), hasLength(1));
    expect(relaunched.session.noteFor(StrategyPhase.teleop), 'hold left side');
  });

  test('Selecting erase tool keeps phase content and stays selected', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.selectPhase(StrategyPhase.teleop);
    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();

    controller.selectTool(StrategyTool.delete);

    expect(controller.session.strokesFor(StrategyPhase.teleop), hasLength(1));
    expect(controller.session.selectedTool, StrategyTool.delete);
  });

  test('eraseAt removes only the tapped stroke', () async {
    const size = Size(1000, 500);
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.selectPhase(StrategyPhase.teleop);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();
    controller.startStroke(const StrategyPoint(0.7, 0.7));
    controller.extendStroke(const StrategyPoint(0.8, 0.8));
    controller.finishStroke();

    controller.selectTool(StrategyTool.delete);

    expect(controller.eraseAt(const Offset(150, 125), size), isTrue);

    final strokes = controller.session.strokesFor(StrategyPhase.teleop);
    expect(strokes, hasLength(1));
    expect(strokes.first.points.first.x, 0.7);

    expect(controller.eraseAt(const Offset(500, 100), size), isFalse);
    expect(controller.session.strokesFor(StrategyPhase.teleop), hasLength(1));
  });

  test('eraseAt removes a marker before an overlapping stroke', () async {
    const size = Size(1000, 500);
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.startStroke(const StrategyPoint(0.4, 0.6));
    controller.extendStroke(const StrategyPoint(0.6, 0.6));
    controller.finishStroke();
    controller.selectTool(StrategyTool.robot);
    controller.placeRobot(const StrategyPoint(0.5, 0.6));

    controller.selectTool(StrategyTool.delete);

    final phase = controller.session.selectedPhase;
    expect(controller.eraseAt(const Offset(500, 300), size), isTrue);
    expect(controller.session.markersFor(phase), isEmpty);
    expect(controller.session.strokesFor(phase), hasLength(1));

    expect(controller.eraseAt(const Offset(500, 300), size), isTrue);
    expect(controller.session.strokesFor(phase), isEmpty);
  });

  test('eraseAt is a no-op when the erase tool is not selected', () async {
    const size = Size(1000, 500);
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();

    expect(controller.session.selectedTool, StrategyTool.draw);
    expect(controller.eraseAt(const Offset(150, 125), size), isFalse);
    expect(
      controller.session.strokesFor(controller.session.selectedPhase),
      hasLength(1),
    );
  });

  test('eraseAt persists the removal across relaunch', () async {
    const size = Size(1000, 500);
    final directory = FakeMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();

    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();
    controller.selectTool(StrategyTool.delete);
    expect(controller.eraseAt(const Offset(150, 125), size), isTrue);
    await controller.saveNow();

    final relaunched = StrategyController(directory: directory);
    await relaunched.bootstrap();
    expect(
      relaunched.session.strokesFor(relaunched.session.selectedPhase),
      isEmpty,
    );
  });

  test('restoreSnapshot undoes a per-element erase', () async {
    const size = Size(1000, 500);
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();
    controller.selectTool(StrategyTool.delete);

    final snapshot = controller.captureSnapshot();
    expect(controller.eraseAt(const Offset(150, 125), size), isTrue);
    expect(
      controller.session.strokesFor(controller.session.selectedPhase),
      isEmpty,
    );

    controller.restoreSnapshot(snapshot);
    expect(
      controller.session.strokesFor(controller.session.selectedPhase),
      hasLength(1),
    );
  });

  test('restoreSnapshot undoes a clearAll', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.selectPhase(StrategyPhase.teleop);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();
    controller.updateNote('press the bumper');

    final snapshot = controller.captureSnapshot();

    controller.clearAll();
    expect(controller.session.strokesFor(StrategyPhase.teleop), isEmpty);
    expect(controller.session.noteFor(StrategyPhase.teleop), isEmpty);

    controller.restoreSnapshot(snapshot);
    expect(controller.session.strokesFor(StrategyPhase.teleop), hasLength(1));
    expect(
      controller.session.noteFor(StrategyPhase.teleop),
      'press the bumper',
    );
  });

  test('restoreSnapshot is a no-op when the active match changed', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.extendStroke(const StrategyPoint(0.2, 0.3));
    controller.finishStroke();
    final snapshot = controller.captureSnapshot();

    await controller.createMatch();
    final freshId = controller.session.id;
    controller.restoreSnapshot(snapshot);

    expect(controller.session.id, freshId);
    expect(
      controller.session.strokesFor(controller.session.selectedPhase),
      isEmpty,
    );
  });

  test('createMatch opens a new match and keeps the previous one', () async {
    final directory = FakeMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();
    final firstId = controller.session.id;

    controller.selectPhase(StrategyPhase.teleop);
    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.finishStroke();
    await controller.saveNow();

    final created = await controller.createMatch(
      eventName: 'Houston',
      matchNumber: 12,
    );

    expect(created.id, isNot(firstId));
    expect(controller.session.id, created.id);
    expect(controller.session.eventName, 'Houston');
    expect(controller.session.matchNumber, 12);
    expect(controller.session.strokesFor(StrategyPhase.teleop), isEmpty);

    final all = await controller.listMatches();
    expect(all.map((m) => m.id), containsAll(<String>[firstId, created.id]));
  });

  test('openMatch swaps active session without losing drawings', () async {
    final directory = FakeMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();
    final firstId = controller.session.id;

    controller.selectPhase(StrategyPhase.teleop);
    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.1, 0.2));
    controller.finishStroke();
    await controller.saveNow();

    final created = await controller.createMatch(
      eventName: 'B',
      matchNumber: 2,
    );
    controller.selectPhase(StrategyPhase.auton);
    controller.selectTool(StrategyTool.draw);
    controller.startStroke(const StrategyPoint(0.5, 0.5));
    controller.finishStroke();
    await controller.saveNow();

    await controller.openMatch(firstId);
    expect(controller.session.id, firstId);
    expect(controller.session.strokesFor(StrategyPhase.teleop), hasLength(1));

    await controller.openMatch(created.id);
    expect(controller.session.id, created.id);
    expect(controller.session.strokesFor(StrategyPhase.auton), hasLength(1));
  });

  test(
    'deleteMatch removes the active match and falls back to another',
    () async {
      final directory = FakeMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final firstId = controller.session.id;
      final created = await controller.createMatch();
      expect(controller.session.id, created.id);

      await controller.deleteMatch(created.id);

      expect(controller.session.id, firstId);
      final remaining = await controller.listMatches();
      expect(remaining.map((m) => m.id), <String>[firstId]);
    },
  );

  test('deleteMatch of last match creates a fresh empty match', () async {
    final directory = FakeMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();
    final onlyId = controller.session.id;

    await controller.deleteMatch(onlyId);

    expect(controller.session.id, isNot(onlyId));
    final remaining = await controller.listMatches();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, controller.session.id);
  });

  test('Bootstrap migrates the legacy single-blob draft', () async {
    final legacySession = StrategySession.create();
    legacySession.eventName = 'Legacy';
    legacySession.matchNumber = 7;
    legacySession.notesByPhase[StrategyPhase.auton] = 'imported';

    SharedPreferences.setMockInitialValues(<String, Object>{
      'strategy_session_draft': jsonEncode(legacySession.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final directory = SharedPreferencesMatchDirectory(preferences: prefs);

    final controller = StrategyController(directory: directory);
    await controller.bootstrap();

    expect(controller.session.id, legacySession.id);
    expect(controller.session.eventName, 'Legacy');
    expect(controller.session.matchNumber, 7);
    expect(controller.session.noteFor(StrategyPhase.auton), 'imported');

    final matches = await controller.listMatches();
    expect(matches.map((m) => m.id), <String>[legacySession.id]);

    expect(prefs.getString('strategy_session_draft'), isNull);

    final secondDirectory = SharedPreferencesMatchDirectory(preferences: prefs);
    final reopened = await secondDirectory.listMatches();
    expect(reopened, hasLength(1));
  });

  test(
    'autoPlaceTeams places teams at standard FRC starting positions',
    () async {
      final controller = StrategyController(directory: FakeMatchDirectory());
      await controller.bootstrap();

      controller.setAlliance('Red');
      controller.loadTeamsFromText('3847, 2714, 5114');
      controller.selectPhase(StrategyPhase.auton);

      controller.autoPlaceTeams();

      final markers = controller.session.markersFor(StrategyPhase.auton);
      expect(markers, hasLength(3));

      for (final marker in markers) {
        expect(marker.position.x, closeTo(0.125, 0.01));
        expect(marker.alliance, 'Red');
      }

      final ys = markers.map((m) => m.position.y).toList()..sort();
      expect(ys[0], closeTo(0.2, 0.01));
      expect(ys[1], closeTo(0.5, 0.01));
      expect(ys[2], closeTo(0.8, 0.01));
    },
  );

  test('autoPlaceTeams splits 6 teams across both alliance sides', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.setAlliance('Blue');
    controller.loadTeamsFromText('1, 2, 3, 4, 5, 6');
    controller.selectPhase(StrategyPhase.teleop);

    controller.autoPlaceTeams();

    final markers = controller.session.markersFor(StrategyPhase.teleop);
    expect(markers, hasLength(6));

    final blueMarkers = markers.take(3).toList();
    for (final m in blueMarkers) {
      expect(m.position.x, closeTo(0.875, 0.01));
      expect(m.alliance, 'Blue');
    }

    final redMarkers = markers.skip(3).toList();
    for (final m in redMarkers) {
      expect(m.position.x, closeTo(0.125, 0.01));
      expect(m.alliance, 'Red');
    }
  });

  test('autoPlaceTeams replaces existing markers for the phase', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.setAlliance('Red');
    controller.loadTeamsFromText('3847');
    controller.selectTool(StrategyTool.robot);
    controller.placeRobot(const StrategyPoint(0.5, 0.5));
    controller.placeRobot(const StrategyPoint(0.6, 0.6));

    controller.autoPlaceTeams();

    final markers = controller.session.markersFor(
      controller.session.selectedPhase,
    );
    expect(markers, hasLength(1));
    expect(markers.first.teamNumber, 3847);
  });

  test('autoPlaceTeams is a no-op when no teams are loaded', () async {
    final controller = StrategyController(directory: FakeMatchDirectory());
    await controller.bootstrap();

    controller.autoPlaceTeams();

    expect(
      controller.session.markersFor(controller.session.selectedPhase),
      isEmpty,
    );
  });

  test('a failed save does not wedge the save queue', () async {
    final directory = _FlakyMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();

    directory.failNextSave = true;
    controller.startStroke(const StrategyPoint(0.1, 0.1));
    controller.finishStroke();
    await controller.saveNow();

    controller.startStroke(const StrategyPoint(0.5, 0.5));
    controller.finishStroke();
    await controller.saveNow();

    final relaunched = StrategyController(directory: directory);
    await relaunched.bootstrap();
    expect(
      relaunched.session.strokesFor(relaunched.session.selectedPhase),
      isNotEmpty,
    );
  });

  test('a failed save marks failedWrites, a later one clears it', () async {
    final directory = _FlakyMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();

    expect(controller.failedWrites.hasFailures, isFalse);

    controller.startStroke(const StrategyPoint(0.1, 0.1));
    controller.finishStroke();
    await controller.saveNow();
    expect(controller.failedWrites.hasFailures, isFalse);

    directory.failNextSave = true;
    await controller.saveNow();

    expect(controller.failedWrites.hasFailures, isTrue);
    expect(controller.failedWrites.unlandedCount, 1);
    expect(controller.failedWrites.lastFailureAt, isNotNull);

    await controller.saveNow();

    expect(controller.failedWrites.hasFailures, isFalse);
    expect(controller.failedWrites.unlandedCount, 0);
    expect(controller.failedWrites.lastFailureAt, isNull);
  });

  test('one failed save does not stop later saves from landing', () async {
    final directory = _FlakyMatchDirectory();
    final controller = StrategyController(directory: directory);
    await controller.bootstrap();

    directory.failNextSave = true;
    controller.startStroke(const StrategyPoint(0.1, 0.1));
    controller.finishStroke();
    await controller.saveNow();

    controller.startStroke(const StrategyPoint(0.9, 0.9));
    controller.finishStroke();
    await controller.saveNow();

    final relaunched = StrategyController(directory: directory);
    await relaunched.bootstrap();
    expect(
      relaunched.session.strokesFor(relaunched.session.selectedPhase),
      isNotEmpty,
    );
  });

  test(
    'a stroke persisted mid-createMatch cannot clobber the new match',
    () async {
      final directory = LaggyMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final firstId = controller.session.id;

      final gate = Completer<void>();
      directory.firstSaveGate = gate;
      controller.selectTool(StrategyTool.draw);
      controller.startStroke(const StrategyPoint(0.1, 0.2));
      controller.finishStroke();

      final pendingCreate = controller.createMatch(eventName: 'Houston');
      gate.complete();
      final created = await pendingCreate;

      final all = await controller.listMatches();
      expect(all.map((m) => m.id), containsAll(<String>[firstId, created.id]));
      final old = await directory.loadMatch(firstId);
      expect(old, isNotNull);
      expect(old!.strokesFor(old.selectedPhase), isNotEmpty);
    },
  );

  group('corrupt stored data tolerance', () {
    test('StrategySession.fromJson survives wrong-typed fields', () {
      final session = StrategySession.fromJson(<String, dynamic>{
        'id': 42,
        'eventName': <String>[],
        'matchNumber': 'three',
        'alliance': 7,
        'teamNumbers': 'not a list',
        'selectedPhase': 'warp',
        'selectedTool': 9,
        'selectedFieldId': 11,
        'selectedRobotTeam': 'abc',
        'updatedAt': false,
        'strokesByPhase': 'nope',
        'markersByPhase': 3,
        'notesByPhase': <dynamic>[],
      });

      expect(session.id, isNotEmpty);
      expect(session.eventName, '');
      expect(session.matchNumber, 1);
      expect(session.alliance, 'Red');
      expect(session.teamNumbers, isEmpty);
      expect(session.selectedPhase, StrategyPhase.auton);
      expect(session.selectedTool, StrategyTool.draw);
      expect(session.selectedFieldId, kLatestFieldId);
      expect(session.selectedRobotTeam, isNull);
    });

    test('corrupt strokes and markers are skipped; valid ones survive', () {
      final valid = StrategySession.create(id: 'seed');
      valid.strokesByPhase[StrategyPhase.teleop]!.add(
        StrategyStroke(
          phase: StrategyPhase.teleop,
          points: const <StrategyPoint>[StrategyPoint(0.1, 0.2)],
        ),
      );
      valid.markersByPhase[StrategyPhase.teleop]!.add(
        RobotMarker(
          phase: StrategyPhase.teleop,
          position: const StrategyPoint(0.5, 0.5),
          teamNumber: 3847,
        ),
      );

      final json =
          jsonDecode(jsonEncode(valid.toJson())) as Map<String, dynamic>;
      final strokes = json['strokesByPhase'] as Map<String, dynamic>;
      final markers = json['markersByPhase'] as Map<String, dynamic>;
      (strokes['teleop'] as List<dynamic>).add('not a stroke');
      (markers['teleop'] as List<dynamic>).insert(0, <String, dynamic>{
        'phase': 'teleop',
        'position': 'broken',
      });
      strokes['hyperspace'] = <dynamic>[];

      final restored = StrategySession.fromJson(json);
      expect(restored.strokesFor(StrategyPhase.teleop), hasLength(1));
      expect(
        restored.strokesFor(StrategyPhase.teleop).single.points,
        hasLength(1),
      );
      final marker = restored.markersFor(StrategyPhase.teleop).single;
      expect(marker.teamNumber, 3847);
    });

    test('StrategyStroke.fromJson skips bad points and unknown phase', () {
      final stroke = StrategyStroke.fromJson(<String, dynamic>{
        'phase': 'banana',
        'colorValue': 'red',
        'points': <dynamic>[
          <String, dynamic>{'x': 0.1, 'y': 0.2},
          <String, dynamic>{'x': 'bad', 'y': 0.3},
          'not a point',
        ],
      });

      expect(stroke.phase, StrategyPhase.auton);
      expect(stroke.points, hasLength(1));
    });

    test('RobotMarker.fromJson tolerates bad optional fields', () {
      final marker = RobotMarker.fromJson(<String, dynamic>{
        'phase': 'nope',
        'position': <String, dynamic>{'x': 0.4, 'y': 0.6},
        'teamNumber': 3847.0,
        'label': 99,
        'alliance': 12,
      });

      expect(marker.phase, StrategyPhase.auton);
      expect(marker.teamNumber, 3847);
      expect(marker.label, isNull);
      expect(marker.alliance, 'Red');
    });

    test('a failed bootstrap is not cached, so a retry re-runs it', () async {
      final directory = _FlakyMatchDirectory()..failNextActiveIdRead = true;
      final controller = StrategyController(directory: directory);

      await expectLater(controller.bootstrap(), throwsStateError);
      expect(controller.isReady, isFalse);

      await controller.bootstrap();
      expect(controller.isReady, isTrue);
    });
  });

  group('board sync', () {
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 700));

    test('rapid edits coalesce into one push', () async {
      final sync = FakeStrategyBoardSyncService();
      final controller = StrategyController(
        directory: FakeMatchDirectory(),
        syncService: sync,
      );
      await controller.bootstrap();

      controller.setMatchNumber('7');
      controller.setAlliance('Blue');
      controller.setEventName('Test Event');
      expect(sync.pushed, isEmpty);

      await settle();
      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.single.eventName, 'Test Event');
    });

    test('dispose flushes a pending upload instead of dropping it', () async {
      final sync = FakeStrategyBoardSyncService();
      final controller = StrategyController(
        directory: FakeMatchDirectory(),
        syncService: sync,
      );
      await controller.bootstrap();

      controller.setEventName('Flushed Event');
      controller.dispose();
      await pumpEventQueue();

      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.single.eventName, 'Flushed Event');
      expect(sync.disposed, isTrue);
    });

    test('deleteMatch without a sync service does not throw', () async {
      final controller = StrategyController(directory: FakeMatchDirectory());
      await controller.bootstrap();
      final id = controller.session.id;

      await controller.deleteMatch(id);

      expect(controller.session.id, isNot(id));
    });

    test('createMatch pushes without waiting for a later edit', () async {
      final sync = FakeStrategyBoardSyncService();
      final controller = StrategyController(
        directory: FakeMatchDirectory(),
        syncService: sync,
      );
      await controller.bootstrap();

      await controller.createMatch(eventName: 'New Event', matchNumber: 12);
      await pumpEventQueue();

      expect(sync.pushed.map((b) => b.eventName), contains('New Event'));
    });

    test(
      'openRemoteBoard adopts a teammate board as the active match',
      () async {
        final sync = FakeStrategyBoardSyncService();
        final directory = FakeMatchDirectory();
        final controller = StrategyController(
          directory: directory,
          syncService: sync,
        );
        await controller.bootstrap();

        final remote = StrategySession.create(id: 'remote-board')
          ..eventName = 'Teammate Event'
          ..matchNumber = 42;
        sync.emitRemote([remote]);
        await pumpEventQueue();
        expect(
          controller.remoteBoards.map((b) => b.id),
          contains('remote-board'),
        );

        await controller.openRemoteBoard('remote-board');

        expect(controller.session.id, 'remote-board');
        expect(controller.session.matchNumber, 42);

        expect(await directory.getActiveMatchId(), 'remote-board');
        expect(
          (await directory.listMatches()).map((m) => m.id),
          contains('remote-board'),
        );
      },
    );

    test(
      'openRemoteBoard ignores an unknown id and the active board',
      () async {
        final sync = FakeStrategyBoardSyncService();
        final controller = StrategyController(
          directory: FakeMatchDirectory(),
          syncService: sync,
        );
        await controller.bootstrap();
        final activeId = controller.session.id;

        await controller.openRemoteBoard('nope');
        expect(controller.session.id, activeId);

        await controller.openRemoteBoard(activeId);
        expect(controller.session.id, activeId);
      },
    );

    test('deleteMatch removes the remote copy when syncing', () async {
      final sync = FakeStrategyBoardSyncService();
      final controller = StrategyController(
        directory: FakeMatchDirectory(),
        syncService: sync,
      );
      await controller.bootstrap();
      final id = controller.session.id;

      await controller.deleteMatch(id);
      await pumpEventQueue();

      expect(sync.deleted, contains(id));
    });

    test('payload never writes a null authorDisplayName', () {
      final json = prepareBoardPayload(
        StrategySession.create(),
        'uid-1',
        null,
        DateTime.utc(2026),
      );

      expect(json['authorUid'], 'uid-1');
      expect(json['authorDisplayName'], '');
    });
  });

  group('local persist debounce', () {
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 700));

    test('rapid touches coalesce into one directory save', () async {
      final directory = LaggyMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final initialSaveCount = directory.savedSessions.length;

      controller.setMatchNumber('7');
      controller.setAlliance('Blue');
      controller.setEventName('Test Event');
      expect(directory.savedSessions, hasLength(initialSaveCount));

      await settle();
      expect(directory.savedSessions, hasLength(initialSaveCount + 1));
      expect(directory.savedSessions.last.eventName, 'Test Event');
    });

    test(
      'dispose flushes a pending local save instead of dropping it',
      () async {
        final directory = LaggyMatchDirectory();
        final controller = StrategyController(directory: directory);
        await controller.bootstrap();
        final initialSaveCount = directory.savedSessions.length;

        controller.setEventName('Flushed Event');
        controller.dispose();
        await pumpEventQueue();

        expect(directory.savedSessions, hasLength(initialSaveCount + 1));
        expect(directory.savedSessions.last.eventName, 'Flushed Event');
      },
    );

    test('saveNow flushes a pending local save immediately', () async {
      final directory = LaggyMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final initialSaveCount = directory.savedSessions.length;

      controller.setEventName('Immediate Event');
      await controller.saveNow();

      expect(directory.savedSessions, hasLength(initialSaveCount + 1));
      expect(directory.savedSessions.last.eventName, 'Immediate Event');
    });

    test('deleting a match drops its pending local save instead of resurrecting it', () async {
      final directory = LaggyMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final id = controller.session.id;

      controller.setEventName('Should Not Land');
      await controller.deleteMatch(id);
      await settle();

      expect(await directory.loadMatch(id), isNull);
    });

    test('AppLifecycleState.paused flushes a pending local save', () async {
      final directory = LaggyMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final initialSaveCount = directory.savedSessions.length;

      controller.setEventName('Backgrounded Event');
      expect(directory.savedSessions, hasLength(initialSaveCount));

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(directory.savedSessions, hasLength(initialSaveCount + 1));
      expect(directory.savedSessions.last.eventName, 'Backgrounded Event');
    });

    test('AppLifecycleState.hidden flushes a pending local save', () async {
      final directory = LaggyMatchDirectory();
      final controller = StrategyController(directory: directory);
      await controller.bootstrap();
      final initialSaveCount = directory.savedSessions.length;

      controller.setEventName('Hidden Event');
      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await pumpEventQueue();

      expect(directory.savedSessions, hasLength(initialSaveCount + 1));
      expect(directory.savedSessions.last.eventName, 'Hidden Event');
    });

    test(
      'AppLifecycleState.resumed does not flush a pending local save early',
      () async {
        final directory = LaggyMatchDirectory();
        final controller = StrategyController(directory: directory);
        await controller.bootstrap();
        final initialSaveCount = directory.savedSessions.length;

        controller.setEventName('Still Pending');
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await pumpEventQueue();

        expect(directory.savedSessions, hasLength(initialSaveCount));
      },
    );
  });
}
