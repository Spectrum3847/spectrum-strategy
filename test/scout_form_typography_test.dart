import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';

const _section = ScoutConfigSection(
  name: 'Autonomous',
  fields: <ScoutConfigField>[
    ScoutConfigField(
      title: 'Coral L1',
      code: 'coralL1',
      type: ScoutFieldType.counter,
    ),
    ScoutConfigField(title: 'Notes', code: 'notes', type: ScoutFieldType.text),
  ],
);

Future<void> _pumpForm(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScoutFormSection(
            section: _section,
            keyPrefix: 'scout-field',
            values: <String, dynamic>{'coralL1': 4},
            textControllers: <String, TextEditingController>{
              'notes': TextEditingController(),
            },
            onFieldChanged: (String code, dynamic value) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextStyle _styleOf(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style!;
}

void main() {
  testWidgets('field labels are large and bold enough to read at a glance', (
    tester,
  ) async {
    await _pumpForm(tester);

    final label = _styleOf(tester, 'Coral L1');
    expect(label.fontSize, 15);
    expect(label.fontWeight, FontWeight.w700);
  });

  testWidgets('the counter value is the biggest thing in the field', (
    tester,
  ) async {
    await _pumpForm(tester);

    final value = _styleOf(tester, '4');
    expect(value.fontSize, 24);
    expect(value.fontWeight, FontWeight.w700);
    expect(
      value.fontSize!,
      greaterThan(_styleOf(tester, 'Coral L1').fontSize!),
    );
  });

  testWidgets('typed values are larger than the app-wide body scale', (
    tester,
  ) async {
    await _pumpForm(tester);

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('scout-field-notes')),
    );
    expect(field.style?.fontSize, 16);
  });
}
