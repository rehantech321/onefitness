import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "app_colors.dart";

class AppTheme {
  AppTheme._();

  /// Built from whichever palette is active, so the Material defaults
  /// (dialogs, text selection, the SnackBar, scrollbars) follow the same
  /// colours the app's own widgets read from [AppColors] — otherwise light
  /// mode would be a light app with dark dialogs.
  ///
  /// [AppColors.apply] must run before this is called; [themeFor] does both
  /// together so they can't drift.
  static ThemeData get current {
    final p = AppColors.palette;
    final base = p.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      colorScheme: base.colorScheme.copyWith(
        surface: p.bg,
        onSurface: p.txt,
        primary: p.gold,
        onPrimary: p.onGold,
        secondary: p.gold,
        onSecondary: p.onGold,
        error: p.danger,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.gold,
          foregroundColor: p.onGold,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.gold,
          foregroundColor: p.onGold,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStatePropertyAll(p.onGold),
      ),
      textTheme: base.textTheme.apply(bodyColor: p.txt, displayColor: p.txt),
      // A dialog left on the Material default is the most visible way a
      // half-converted theme shows itself.
      dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.card,
        contentTextStyle: TextStyle(color: p.txt),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: p.line,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.txt,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Resolves [mode] against the device setting, installs the matching
  /// palette, and returns the ThemeData built from it. One call so the
  /// palette and the ThemeData can never describe different themes.
  static ThemeData themeFor(ThemeMode mode, Brightness platformBrightness) {
    AppColors.apply(paletteFor(mode, platformBrightness));
    return current;
  }

  /// Which palette [mode] means, with "match phone" resolved.
  ///
  /// Separate from [themeFor] so a caller can install it itself and see
  /// [AppColors.apply]'s return value — whether the palette actually changed
  /// is what tells the root whether the screens below need rebuilding.
  static AppPalette paletteFor(ThemeMode mode, Brightness platformBrightness) {
    final wantsDark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    return wantsDark ? AppPalette.dark : AppPalette.light;
  }
}
