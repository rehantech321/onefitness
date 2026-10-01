import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "app_colors.dart";

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.bg,
        primary: AppColors.gold,
        onPrimary: AppColors.onGold,
        secondary: AppColors.gold,
        onSecondary: AppColors.onGold,
        error: AppColors.danger,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.onGold,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.onGold,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: const WidgetStatePropertyAll(AppColors.onGold),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.txt,
        displayColor: AppColors.txt,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: AppColors.line,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
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
}
