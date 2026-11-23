import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF48E5D2);
  static const Color primaryDark = Color(0xFF16AFA7);

  static const Color background = Color(0xFF0B1115);
  static const Color surface = Color(0xFF141E24);
  static const Color surfaceRaised = Color(0xFF1A272E);

  static const Color sidebar = Color(0xFF080D10);

  static const Color textPrimary = Color(0xFFE7F0F1);
  static const Color textSecondary = Color(0xFF9AADB2);

  static const Color success = Color(0xFF57D99A);
  static const Color warning = Color(0xFFFFC45B);
  static const Color danger = Color(0xFFFF6B7F);

  static const Color border = Color(0xFF293940);
  // Açık tema
  static const Color lightBackground = Color(0xFFE4E9E4);
  static const Color lightSurface = Color.fromARGB(255, 241, 241, 241);
  static const Color lightSurfaceRaised = Color(0xFFE9EDE6);
  static const Color lightTextPrimary = Color(0xFF14211D);
  static const Color lightTextSecondary = Color(0xFF4A5C56);
  static const Color lightBorder = Color(0xFFCBD4CC);
  static const Color lightSidebar = Color(0xFFCBD4CC); // açık sidebar

  /// Rozet / durum arka planı için yumuşak ton: AppColors.soft(AppColors.success)
  static Color soft(Color color, [double alpha = 0.14]) =>
      color.withValues(alpha: alpha);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Color lightPrimary = Color(0xFF0E9F95);
  static const Color lightPrimaryDark = Color(0xFF0A7A73);

  static const LinearGradient lightPrimaryGradient = LinearGradient(
    colors: [lightPrimary, lightPrimaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
