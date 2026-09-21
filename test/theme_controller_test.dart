import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults to system theme and glass off', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.themeMode, ThemeMode.system);
    expect(controller.liquidGlass, isFalse);
  });

  test('defaults glass on for iOS with no saved preference', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isTrue);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    test('defaults glass off for $platform with no saved preference', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final controller = ThemeController();
      await controller.bootstrap();

      expect(controller.liquidGlass, isFalse);
    });
  }

  test('a saved false preference wins over the iOS default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_liquid_glass': false,
    });

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isFalse);
  });

  test('a saved true preference wins over the macOS default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_liquid_glass': true,
    });

    final controller = ThemeController();
    await controller.bootstrap();

    expect(controller.liquidGlass, isTrue);
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
