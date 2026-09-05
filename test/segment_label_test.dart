import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';
import 'package:spectrumstrategy/src/widgets/segment_label.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

const double _labelRoomFloor = 0.6;

const Size _phone = Size(360, 760);
const Size _tablet = Size(1100, 900);

void main() {
  Future<void> pumpDatabaseTab(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    await scouting.saveEntry(
      ScoutEntry(
        matchId: 'session-uuid',
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{'matchNumber': 1},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DatabaseTab(
            scoutingController: scouting,
            configController: config,
            eventController: EventController(),
            canEditAnyEntry: false,
            canAddManualEntry: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isTruncated(WidgetTester tester, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(SegmentLabel),
        matching: find.text(label),
      ),
    );
    return paragraph.didExceedMaxLines;
  }

  ({double scale, double natural, double rendered}) labelFit(
    WidgetTester tester,
    String label,
  ) {
    final text = find.text(label);
    final natural = tester
        .renderObject<RenderParagraph>(
          find.descendant(of: find.byType(SegmentLabel), matching: text),
        )
        .size;
    final rendered = tester.getSize(
      find.ancestor(of: text, matching: find.byType(SegmentLabel)),
    );
    return (
      scale: rendered.width / natural.width,
      natural: natural.width,
      rendered: rendered.width,
    );
  }

  const labels = <String>['Table', 'Rows', 'Analysis', 'Coverage'];

  testWidgets('no switcher label is cut short on a phone', (tester) async {
    await pumpDatabaseTab(tester, size: _phone);

    for (final label in labels) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
      expect(isTruncated(tester, label), isFalse, reason: '$label was cut off');
    }
  });

  testWidgets('a phone segment gives its label room to render at full size', (
    tester,
  ) async {
    await pumpDatabaseTab(tester, size: _phone);

    for (final label in labels) {
      final fit = labelFit(tester, label);
      expect(
        fit.scale,
        greaterThanOrEqualTo(_labelRoomFloor),
        reason:
            '$label got ${fit.rendered.toStringAsFixed(1)}px of the '
            '${fit.natural.toStringAsFixed(1)}px the test font asks for, '
            '${(fit.scale * 100).toStringAsFixed(0)}%',
      );
    }
  });

  testWidgets('the phone switcher gives the width to the words', (
    tester,
  ) async {
    await pumpDatabaseTab(tester, size: _phone);

    expect(find.byIcon(Icons.insights_outlined), findsNothing);
    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
  });

  testWidgets('a tablet keeps the icons and the labels', (tester) async {
    await pumpDatabaseTab(tester, size: _tablet);

    expect(find.byIcon(Icons.insights_outlined), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    for (final label in labels) {
      expect(isTruncated(tester, label), isFalse, reason: '$label was cut off');
    }
  });

  testWidgets('a label that fits is not scaled down', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 300, child: SegmentLabel('Coverage')),
          ),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.text('Coverage'));
    final rendered = tester.getSize(find.byType(SegmentLabel));
    expect(rendered.height, box.size.height);
  });
}
