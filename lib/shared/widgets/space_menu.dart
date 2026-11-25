import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [SpaceMenuButton] menüsündeki bir satır.
class SpaceMenuItem<T> {
  const SpaceMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive; // Silme gibi tehlikeli işlemler gül renginde görünür
}

/// Üç nokta düğmesi + kenar çubuğuyla aynı tasarım dilinde açılır menü:
/// her satır, kenar çubuğundaki öğelerle birebir aynı cam kutu, çerçeve,
/// hover'da merkezden yayılan camgöbeği/mor ışıma ve renkleri kullanır.
/// Yer yoksa yukarı doğru açılır; dışarı tıklayınca veya Esc ile kapanır.
class SpaceMenuButton<T> extends StatefulWidget {
  const SpaceMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.tooltip,
    this.icon = Icons.more_vert,
    this.width = 270,
  });

  final List<SpaceMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final IconData icon;
  final double width;

  @override
  State<SpaceMenuButton<T>> createState() => _SpaceMenuButtonState<T>();
}

class _SpaceMenuButtonState<T> extends State<SpaceMenuButton<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  bool get _isOpen => _entry != null;

  void _open() {
    if (_isOpen) return;
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final estimatedHeight = widget.items.length * 56.0 + 20;
    final spaceBelow = screen.height - (origin.dy + box.size.height) - 12;
    final spaceAbove = origin.dy - 12;
    final openUp = spaceBelow < estimatedHeight && spaceAbove > spaceBelow;
    _entry = OverlayEntry(builder: (context) => _buildOverlay(openUp));
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _removeEntry() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _close() {
    if (!_isOpen) return;
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _select(T value) {
    _close();
    widget.onSelected(value);
  }

  Widget _buildOverlay(bool openUp) {
    const radius = 22.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: openUp ? Alignment.topRight : Alignment.bottomRight,
          followerAnchor: openUp ? Alignment.bottomRight : Alignment.topRight,
          offset: Offset(0, openUp ? -6 : 6),
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
            child: Focus(
              autofocus: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * t,
                    alignment: openUp
                        ? Alignment.bottomRight
                        : Alignment.topRight,
                    child: child,
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: SizedBox(
                    width: widget.width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.28),
                            blurRadius: 34,
                            offset: const Offset(0, 14),
                          ),
                          BoxShadow(
                            color: const Color(0xFF22D3EE).withValues(alpha: 0.10),
                            blurRadius: 22,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xD90B1030),
                              borderRadius: BorderRadius.circular(radius),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final item in widget.items)
                                    _SpaceMenuRow<T>(
                                      item: item,
                                      onTap: () => _select(item.value),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        key: _buttonKey,
        tooltip: widget.tooltip,
        onPressed: _isOpen ? _close : _open,
        icon: Icon(widget.icon),
        color: _isOpen ? const Color(0xFF22D3EE) : null,
      ),
    );
  }
}

/// Kenar çubuğundaki `_SidebarItem` ile aynı görünüm (sürekli "pasif" hâl).
class _SpaceMenuRow<T> extends StatefulWidget {
  const _SpaceMenuRow({required this.item, required this.onTap});

  final SpaceMenuItem<T> item;
  final VoidCallback onTap;

  @override
  State<_SpaceMenuRow<T>> createState() => _SpaceMenuRowState<T>();
}

class _SpaceMenuRowState<T> extends State<_SpaceMenuRow<T>> {
  bool _hovering = false;

  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _rose = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final item = widget.item;
    // Silme gibi satırlarda camgöbeği yerine gül rengi kullanılır.
    final accent = item.destructive ? _rose : _cyan;
    final secondary = item.destructive ? _rose : _violet;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _hovering ? 0.075 : 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovering
                ? Color.lerp(Colors.white, accent, 0.45)!.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.09),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (_hovering)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.5,
                        colors: [
                          accent.withValues(alpha: 0.08),
                          secondary.withValues(alpha: 0.04),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(16),
                  hoverColor: Colors.transparent,
                  splashColor: accent.withValues(alpha: 0.12),
                  highlightColor: Colors.white.withValues(alpha: 0.04),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        if (item.icon != null) ...[
                          Icon(
                            item.icon,
                            size: 21,
                            color: item.destructive
                                ? _rose
                                : (_hovering
                                      ? _cyan
                                      : colors.onSurfaceVariant),
                          ),
                          const SizedBox(width: 13),
                        ],
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: item.destructive
                                  ? _rose
                                  : colors.onSurface.withValues(alpha: 0.86),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}