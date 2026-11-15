import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static final ThemeData lightTheme = _build(Brightness.light);
  static final ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF0B1115)
        : const Color(0xFFF4F7F8);
    final surface = isDark ? const Color(0xFF141E24) : Colors.white;
    final raisedSurface = isDark
        ? const Color(0xFF1A272E)
        : const Color(0xFFEDF2F3);
    final sidebar = isDark ? const Color(0xFF080D10) : Colors.white;
    final textPrimary = isDark
        ? const Color(0xFFE7F0F1)
        : const Color(0xFF18252B);
    final textSecondary = isDark
        ? const Color(0xFF9AADB2)
        : const Color(0xFF52636A);
    final border = isDark ? const Color(0xFF293940) : const Color(0xFFD8E1E4);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
        surface: surface,
        primary: AppColors.primary,
        onPrimary: AppColors.sidebar,
        secondary: AppColors.success,
        error: AppColors.danger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raisedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
      ),
      dividerTheme: DividerThemeData(color: border),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sidebar,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : textSecondary,
            fontSize: 12,
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        titleMedium: TextStyle(color: textPrimary),
      ),
    );
  }
}
