import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';

const _section = ScoutConfigSection(
  name: 'Teleop',
  fields: <ScoutConfigField>[
    ScoutConfigField(
      title: 'Fuel Scored',
      code: 'teleopFuelScored',
      type: ScoutFieldType.counter,
      buttons: <int>[1, 5, 10],
    ),
  ],
);

Future<int> _pumpForm(WidgetTester tester, int initial) async {
  var value = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return ScoutFormSection(
              section: _section,
              keyPrefix: 'scout-field',
              values: <String, dynamic>{'teleopFuelScored': value},
              textControllers: const <String, TextEditingController>{},
              onFieldChanged: (String code, dynamic v) {
                setState(() => value = v as int);
              },
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return value;
}

void main() {
  testWidgets('every configured increment gets its own subtract button', (
    tester,
  ) async {
    await _pumpForm(tester, 20);

    for (final label in <String>['-1', '-5', '-10', '+1', '+5', '+10']) {
      expect(
        find.widgetWithText(OutlinedButton, label),
        findsOneWidget,
        reason: 'no $label button rendered for buttons [1, 5, 10]',
      );
    }
  });

  testWidgets('tapping -5 subtracts five, not one', (tester) async {
    await _pumpForm(tester, 20);

    await tester.tap(find.widgetWithText(OutlinedButton, '-5'));
    await tester.pumpAndSettle();

    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('a subtract button that would cross the floor is disabled', (
    tester,
  ) async {
    await _pumpForm(tester, 3);

    final minus5 = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '-5'),
    );
    final minus1 = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '-1'),
    );
    expect(minus5.onPressed, isNull);
    expect(minus1.onPressed, isNotNull);
  });
}
