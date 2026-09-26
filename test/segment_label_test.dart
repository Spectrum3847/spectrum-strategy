import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/widgets/segment_label.dart';

const double _labelRoomFloor = 0.6;

const _label = 'IQM score';

Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: SegmentLabel(_label)),
        ),
      ),
    ),
  );
}

bool isTruncated(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byType(SegmentLabel), matching: find.text(_label)),
  );
  return paragraph.didExceedMaxLines;
}

({double scale, double natural, double rendered}) labelFit(
  WidgetTester tester,
) {
  final text = find.text(_label);
  final natural = tester
      .renderObject<RenderParagraph>(
        find.descendant(of: find.byType(SegmentLabel), matching: text),
      )
      .size;
  final rendered = tester.getSize(find.byType(SegmentLabel));
  return (
    scale: rendered.width / natural.width,
    natural: natural.width,
    rendered: rendered.width,
  );
}

void main() {
  testWidgets('a label squeezed far past its own width is never cut short', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 40);

    expect(find.text(_label), findsOneWidget);
    expect(isTruncated(tester), isFalse, reason: '$_label was cut off');
  });

  testWidgets('a squeezed label still keeps a floor of the room it asks for', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 90);

    final fit = labelFit(tester);

    expect(fit.scale, lessThan(1.0));
    expect(
      fit.scale,
      greaterThanOrEqualTo(_labelRoomFloor),
      reason:
          '$_label got ${fit.rendered.toStringAsFixed(1)}px of the '
          '${fit.natural.toStringAsFixed(1)}px the test font asks for, '
          '${(fit.scale * 100).toStringAsFixed(0)}%',
    );
  });

  testWidgets('a label that fits is not scaled down', (tester) async {
    await _pumpAtWidth(tester, 300);

    final box = tester.renderObject<RenderBox>(find.text(_label));
    final rendered = tester.getSize(find.byType(SegmentLabel));
    expect(rendered.height, box.size.height);
  });
}
