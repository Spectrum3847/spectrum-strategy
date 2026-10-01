import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/services/desktop_tray_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to enabled with no persisted preference', () async {
    final setting = MinimizeToTraySetting();
    expect(await setting.isEnabled(), isTrue);
  });

  test('setEnabled(false) persists and a later instance reads it', () async {
    await MinimizeToTraySetting().setEnabled(false);
    expect(await MinimizeToTraySetting().isEnabled(), isFalse);
  });

  test('setEnabled(true) after a false persists true', () async {
    final setting = MinimizeToTraySetting();
    await setting.setEnabled(false);
    await setting.setEnabled(true);
    expect(await MinimizeToTraySetting().isEnabled(), isTrue);
  });
}
