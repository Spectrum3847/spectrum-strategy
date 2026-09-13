import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults to system theme and glass off', () async {
    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.themeMode, ThemeMode.system);
    expect(controller.liquidGlass, isFalse);
  });

  test('liquid glass survives a relaunch', () async {
    final first = ThemeController();
    await first.bootstrap();
    await first.setLiquidGlass(true);

    final second = ThemeController();
    await second.bootstrap();

    expect(second.liquidGlass, isTrue);
  });

  test('a stored glass flag of false stays false', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_liquid_glass': false,
    });

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isFalse);
  });

  test(
    'setting glass notifies once, and re-setting the same value does not',
    () async {
      final controller = ThemeController();
      await controller.bootstrap();

      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setLiquidGlass(true);
      expect(notifications, 1);

      await controller.setLiquidGlass(true);
      expect(notifications, 1);

      await controller.setLiquidGlass(false);
      expect(notifications, 2);
    },
  );
}
