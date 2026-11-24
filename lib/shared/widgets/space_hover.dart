import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Kartların içine konan "buzlu cam" + fütüristik hover efekti:
///  * arkadaki görüntüyü bulanıklaştırır (buzlu cam),
///  * fare üstüne gelince imleci takip eden ışık hüzmesi (spotlight),
///  * kenarlarda camgöbeği → mor → pembe parlayan çerçeve.
/// Reklam alanı kartlarındaki "durum rengiyle dolma" efektine dokunmaz.
class SpaceHover extends StatefulWidget {
  const SpaceHover({
    super.key,
    required this.child,
    this.radius = 20,
    this.blur = 10,
  });

  final Widget child;
  final double radius;
  final double blur;

  @override
  State<SpaceHover> createState() => _SpaceHoverState();
}

class _SpaceHoverState extends State<SpaceHover> {
  bool _hovering = false;
  Offset _position = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: MouseRegion(
          onEnter: (event) => setState(() {
            _hovering = true;
            _position = event.localPosition;
          }),
          onHover: (event) => setState(() => _position = event.localPosition),
          onExit: (_) => setState(() => _hovering = false),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _hovering ? 1 : 0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SpaceHoverPainter(
                        progress: t,
                        position: _position,
                        radius: widget.radius,
                      ),
                    ),
                  ),
                ),
                child!,
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _SpaceHoverPainter extends CustomPainter {
  const _SpaceHoverPainter({
    required this.progress,
    required this.position,
    required this.radius,
  });

  final double progress;
  final Offset position;
  final double radius;

  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _pink = Color(0xFFEC4899);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // İmleci takip eden ışık hüzmesi
    final center = Offset(
      position.dx.clamp(0.0, size.width),
      position.dy.clamp(0.0, size.height),
    );
    final spot = ui.Gradient.radial(
      center,
      260,
      [
        _cyan.withValues(alpha: 0.18 * progress),
        _violet.withValues(alpha: 0.08 * progress),
        Colors.transparent,
      ],
      const [0.0, 0.5, 1.0],
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, Paint()..shader = spot);
    canvas.restore();

    // Parlayan çerçeve
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          _cyan.withValues(alpha: 0.8 * progress),
          _violet.withValues(alpha: 0.8 * progress),
          _pink.withValues(alpha: 0.6 * progress),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRRect(rrect.deflate(0.7), border);
  }

  @override
  bool shouldRepaint(covariant _SpaceHoverPainter old) =>
      old.progress != progress ||
      old.position != position ||
      old.radius != radius;
}