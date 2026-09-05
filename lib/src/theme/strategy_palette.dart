import 'dart:math' show pow;

import 'package:flutter/material.dart';

enum StrategyPhase {
  auton,
  teleop,
  endgame;

  String get label {
    switch (this) {
      case StrategyPhase.auton:
        return 'Auton';
      case StrategyPhase.teleop:
        return 'Teleop';
      case StrategyPhase.endgame:
        return 'Endgame';
    }
  }

  String get shortLabel {
    switch (this) {
      case StrategyPhase.auton:
        return 'A';
      case StrategyPhase.teleop:
        return 'T';
      case StrategyPhase.endgame:
        return 'E';
    }
  }
}

enum StrategyTool {
  draw,
  robot,
  delete;

  String get label {
    switch (this) {
      case StrategyTool.draw:
        return 'Draw';
      case StrategyTool.robot:
        return 'Robot';
      case StrategyTool.delete:
        return 'Erase';
    }
  }
}

StrategyPhase? strategyPhaseByNameOrNull(Object? name) {
  for (final phase in StrategyPhase.values) {
    if (phase.name == name) {
      return phase;
    }
  }
  return null;
}

StrategyTool? strategyToolByNameOrNull(Object? name) {
  for (final tool in StrategyTool.values) {
    if (tool.name == name) {
      return tool;
    }
  }
  return null;
}

class StrategyPalette {
  static const double radiusSm = 4;
  static const double radiusMd = 8;

  static const Color background = Color(0xFFF2ECF7);

  static const Color textMuted = Color(0xFF645870);
  static const Color primary = Color(0xFF3C0060);
  static const Color secondary = Color(0xFFDDD5E7);
  static const Color accent = Color(0xFF73697F);

  static const Color textPrimary = Color(0xFF554962);
  static const Color surface = Color(0xFFEAE1F1);
  static const Color surfaceStrong = Color(0xFFDFD3EA);
  static const Color border = Color(0xFFC9BAD8);
  static const Color grid = Color(0xFFC2AFD3);
  static const Color auton = Color(0xFF3C0060);
  static const Color teleop = Color(0xFF73697F);
  static const Color endgame = Color(0xFF9D8AB0);
  static const Color allianceRed = Color(0xFFC02B2B);
  static const Color allianceBlue = Color(0xFF1F4FA8);

  static const Color onAlliance = Color(0xFFFFFFFF);

  static const Color onPhaseLight = Color(0xFFFFFFFF);
  static const Color onPhaseDark = Color(0xFF141117);

  static const Color error = Color(0xFF98401A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color darkError = Color(0xFFEE652B);
  static const Color darkOnError = Color(0xFF141117);

  static const Color scheduleGreen = Color(0xFF2E7D32);
  static const Color onScheduleGreen = Color(0xFFFFFFFF);
  static const Color darkScheduleGreen = Color(0xFF6FCF8B);
  static const Color darkOnScheduleGreen = Color(0xFF0B2A14);

  static const Color flagSevere = Color(0xFFF3D3D3);
  static const Color flagWarn = Color(0xFFF5DCC2);
  static const Color flagNotice = Color(0xFFE9D9A0);
  static const Color darkFlagSevere = Color(0xFF3E2226);
  static const Color darkFlagWarn = Color(0xFF402C18);
  static const Color darkFlagNotice = Color(0xFF3D3612);

  static const Color darkBackground = Color(0xFF141117);
  static const Color darkSurface = Color(0xFF1E1B22);
  static const Color darkSurfaceStrong = Color(0xFF2A2630);
  static const Color darkPrimary = Color(0xFFCFBCFF);
  static const Color darkOnPrimary = Color(0xFF270057);
  static const Color darkSecondary = Color(0xFF3D3340);

  static const Color darkText = Color(0xFFF1ECF7);
  static const Color darkTextMuted = Color(0xFFCAC2D6);
  static const Color darkOutline = Color(0xFF4A4454);
  static const Color darkSwitchThumbOff = Color(0xFF8B8096);

  static Color metricToneOf(BuildContext context, double? percentile) {
    final muted = _isDark(context) ? darkTextMuted : textMuted;
    if (percentile == null) return muted;
    if (percentile >= 2 / 3) return _isDark(context) ? darkPrimary : auton;

    if (percentile >= 1 / 3) return _isDark(context) ? darkText : textPrimary;
    return muted;
  }

  static Color mutedTextOf(BuildContext context) =>
      _isDark(context) ? darkTextMuted : textMuted;

  static Color surfaceOf(BuildContext context) =>
      _isDark(context) ? darkSurface : surface;

  static Color surfaceStrongOf(BuildContext context) =>
      _isDark(context) ? darkSurfaceStrong : surfaceStrong;

  static Color borderOf(BuildContext context) =>
      _isDark(context) ? darkOutline : border;

  static Color chipSelectedOf(BuildContext context) =>
      _isDark(context) ? darkPrimary : primary;

  static Color onChipSelectedOf(BuildContext context) =>
      _isDark(context) ? darkOnPrimary : onAlliance;

  static Color chipUnselectedOf(BuildContext context) =>
      _isDark(context) ? darkSecondary : secondary;

  static Color onChipUnselectedOf(BuildContext context) =>
      _isDark(context) ? darkText : textPrimary;

  static Color flagSevereOf(BuildContext context) =>
      _isDark(context) ? darkFlagSevere : flagSevere;

  static Color flagWarnOf(BuildContext context) =>
      _isDark(context) ? darkFlagWarn : flagWarn;

  static Color flagNoticeOf(BuildContext context) =>
      _isDark(context) ? darkFlagNotice : flagNotice;

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color gradeColorOf(BuildContext context, double fraction) {
    final f = fraction.isNaN ? 0.5 : fraction.clamp(0.0, 1.0);

    final hue = 124 * f;
    return _isDark(context)
        ? HSLColor.fromAHSL(1, hue, 0.45, 0.22).toColor()
        : HSLColor.fromAHSL(1, hue, 0.55, 0.86).toColor();
  }

  static Color onGradeColorOf(BuildContext context) =>
      _isDark(context) ? darkText : textPrimary;

  static Color phaseColor(StrategyPhase phase) {
    switch (phase) {
      case StrategyPhase.auton:
        return auton;
      case StrategyPhase.teleop:
        return teleop;
      case StrategyPhase.endgame:
        return endgame;
    }
  }

  static Color allianceColor(String alliance) {
    return alliance.toLowerCase() == 'blue' ? allianceBlue : allianceRed;
  }

  static double _relativeLuminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  static double contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static Color onPhaseColor(StrategyPhase phase) {
    final fill = phaseColor(phase);
    if (contrastRatio(onPhaseLight, fill) >= 4.5) return onPhaseLight;
    if (contrastRatio(onPhaseDark, fill) >= 4.5) return onPhaseDark;
    return contrastRatio(onPhaseLight, fill) >= contrastRatio(onPhaseDark, fill)
        ? onPhaseLight
        : onPhaseDark;
  }
}
