import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Uzay temalı, koyu ve "buzlu cam" görünümlü uygulama teması.
class SpaceColors {
  static const Color deep = Color(0xFF060918);
  static const Color night = Color(0xFF0B1030);
  static const Color nebula = Color(0xFF150C33);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color pink = Color(0xFFEC4899);
  static const Color text = Color(0xFFE8ECFF);
  static const Color textMuted = Color(0xFFA7B0D6);
}

class SpaceTheme {
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: SpaceColors.violet,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF8AA2FF),
          onPrimary: const Color(0xFF0B1030),
          secondary: SpaceColors.cyan,
          tertiary: SpaceColors.pink,
          error: const Color(0xFFFB7185),
          surface: const Color(0xFF10152B),
          onSurface: SpaceColors.text,
          onSurfaceVariant: SpaceColors.textMuted,
          outline: const Color(0x4DFFFFFF),
          outlineVariant: const Color(0x24FFFFFF),
          surfaceContainerHighest: const Color(0x26FFFFFF),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: const Color(0xFF141A38),
    );

    const radius14 = BorderRadius.all(Radius.circular(14));
    final glassBorder = OutlineInputBorder(
      borderRadius: radius14,
      borderSide: const BorderSide(color: Color(0x2EFFFFFF)),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: SpaceColors.text,
        displayColor: SpaceColors.text,
      ),
      cardTheme: CardThemeData(
        color: const Color(0x14FFFFFF),
        surfaceTintColor: Colors.transparent,
        shadowColor: SpaceColors.violet.withValues(alpha: 0.35),
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x24FFFFFF)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xF2121733),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        border: glassBorder,
        enabledBorder: glassBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: SpaceColors.cyan, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: Color(0xFFFB7185)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: Color(0xFFFB7185), width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: SpaceColors.textMuted),
        hintStyle: const TextStyle(color: SpaceColors.textMuted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xF2141A38),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1B2245),
        contentTextStyle: const TextStyle(color: SpaceColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0x1FFFFFFF)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6D5BFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SpaceColors.text,
          side: const BorderSide(color: Color(0x3DFFFFFF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF8AA2FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: SpaceColors.textMuted,
        textColor: SpaceColors.text,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xCC0B1030),
        indicatorColor: const Color(0x338AA2FF),
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2245),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        textStyle: const TextStyle(color: SpaceColors.text, fontSize: 12),
      ),
    );
  }
}

/// Tüm uygulamanın arkasındaki uzay zemini: gece gökyüzü, nebula ışımaları, yıldızlar.
class SpaceBackground extends StatelessWidget {
  const SpaceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: _SpaceBackdrop()),
        child,
      ],
    );
  }
}

class _SpaceBackdrop extends StatelessWidget {
  const _SpaceBackdrop();

  Widget _glow(Alignment alignment, Color color, double radius, double alpha) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: alignment,
          radius: radius,
          colors: [color.withValues(alpha: alpha), Colors.transparent],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SpaceColors.deep, SpaceColors.night, SpaceColors.nebula],
            ),
          ),
        ),
        _glow(const Alignment(-0.95, -0.9), SpaceColors.violet, 0.9, 0.30),
        _glow(const Alignment(1.0, 0.85), SpaceColors.cyan, 0.8, 0.18),
        _glow(const Alignment(0.7, -0.5), SpaceColors.pink, 0.6, 0.10),
        const CustomPaint(painter: _StarPainter()),
      ],
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 170; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final r = 0.4 + random.nextDouble() * 1.0;
      paint
        ..maskFilter = null
        ..color = Colors.white.withValues(
          alpha: 0.18 + random.nextDouble() * 0.55,
        );
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
    for (var i = 0; i < 14; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final tint = i.isEven ? SpaceColors.cyan : Colors.white;
      paint
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..color = tint.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(dx, dy), 1.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}