import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'strategy_palette.dart';

const _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(StrategyPalette.radiusSm)),
);

const _minTarget = Size(64, 48);

final _filledButtonTheme = FilledButtonThemeData(
  style: FilledButton.styleFrom(shape: _buttonShape, minimumSize: _minTarget),
);
final _outlinedButtonTheme = OutlinedButtonThemeData(
  style: OutlinedButton.styleFrom(shape: _buttonShape, minimumSize: _minTarget),
);
final _textButtonTheme = TextButtonThemeData(
  style: TextButton.styleFrom(shape: _buttonShape, minimumSize: _minTarget),
);
const _segmentedButtonTheme = SegmentedButtonThemeData(
  style: ButtonStyle(shape: WidgetStatePropertyAll(_buttonShape)),
);

ThemeData buildDarkAppTheme() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final baseTheme = ThemeData.dark(useMaterial3: true);
  const darkTextColor = StrategyPalette.darkText;

  final textTheme = GoogleFonts.overpassTextTheme(baseTheme.textTheme).copyWith(
    titleLarge: GoogleFonts.overpass(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: darkTextColor,
    ),
    titleMedium: GoogleFonts.overpass(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: darkTextColor,
    ),
    bodyLarge: GoogleFonts.overpass(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: darkTextColor,
    ),
    bodyMedium: GoogleFonts.overpass(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: darkTextColor,
    ),
    labelLarge: GoogleFonts.overpass(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: darkTextColor,
    ),
  );

  const darkBackground = StrategyPalette.darkBackground;
  const darkSurface = StrategyPalette.darkSurface;
  const darkSurfaceStrong = StrategyPalette.darkSurfaceStrong;

  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: StrategyPalette.darkPrimary,
      onPrimary: StrategyPalette.darkOnPrimary,
      secondary: StrategyPalette.darkSecondary,
      onSecondary: StrategyPalette.darkText,
      surface: darkBackground,
      onSurface: darkTextColor,
      onSurfaceVariant: StrategyPalette.darkTextMuted,
      error: StrategyPalette.darkError,
      onError: StrategyPalette.darkOnError,
      outline: StrategyPalette.darkOutline,
    ),
    scaffoldBackgroundColor: darkBackground,
    textTheme: textTheme,
    fontFamily: GoogleFonts.overpass().fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        borderSide: BorderSide(color: darkSurfaceStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        borderSide: BorderSide(color: darkSurfaceStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        borderSide: BorderSide(color: StrategyPalette.darkPrimary, width: 1.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      backgroundColor: darkBackground,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      backgroundColor: darkSurfaceStrong,
      selectedColor: StrategyPalette.darkPrimary,
      labelStyle: textTheme.labelLarge?.copyWith(color: darkTextColor),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(
        color: StrategyPalette.darkOnPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return StrategyPalette.darkPrimary;
        }
        return StrategyPalette.darkSwitchThumbOff;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return darkSurfaceStrong;
        }
        return StrategyPalette.darkSurface;
      }),
    ),
    filledButtonTheme: _filledButtonTheme,
    outlinedButtonTheme: _outlinedButtonTheme,
    textButtonTheme: _textButtonTheme,
    segmentedButtonTheme: _segmentedButtonTheme,
  );
}

ThemeData buildAppTheme() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final baseTheme = ThemeData.light(useMaterial3: true);

  final textTheme = GoogleFonts.overpassTextTheme(baseTheme.textTheme).copyWith(
    titleLarge: GoogleFonts.overpass(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: StrategyPalette.textPrimary,
    ),
    titleMedium: GoogleFonts.overpass(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: StrategyPalette.textPrimary,
    ),
    bodyLarge: GoogleFonts.overpass(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: StrategyPalette.textPrimary,
    ),
    bodyMedium: GoogleFonts.overpass(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: StrategyPalette.textPrimary,
    ),
    labelLarge: GoogleFonts.overpass(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: StrategyPalette.textPrimary,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: StrategyPalette.primary,
      onPrimary: Colors.white,
      secondary: StrategyPalette.secondary,
      onSecondary: StrategyPalette.primary,
      surface: StrategyPalette.background,
      onSurface: StrategyPalette.textPrimary,
      onSurfaceVariant: StrategyPalette.textMuted,
      error: StrategyPalette.error,
      onError: StrategyPalette.onError,
      outline: StrategyPalette.border,
    ),
    scaffoldBackgroundColor: StrategyPalette.background,
    textTheme: textTheme,
    fontFamily: GoogleFonts.overpass().fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: StrategyPalette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: StrategyPalette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        borderSide: BorderSide(color: StrategyPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        borderSide: BorderSide(color: StrategyPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
        borderSide: BorderSide(color: StrategyPalette.primary, width: 1.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      backgroundColor: StrategyPalette.background,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StrategyPalette.radiusSm),
        ),
      ),
      backgroundColor: StrategyPalette.secondary,
      selectedColor: StrategyPalette.primary,
      labelStyle: textTheme.labelLarge?.copyWith(
        color: StrategyPalette.textPrimary,
      ),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    filledButtonTheme: _filledButtonTheme,
    outlinedButtonTheme: _outlinedButtonTheme,
    textButtonTheme: _textButtonTheme,
    segmentedButtonTheme: _segmentedButtonTheme,
  );
}
