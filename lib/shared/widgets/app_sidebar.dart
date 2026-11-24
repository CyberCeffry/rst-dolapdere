import 'package:flutter/material.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.visibleIndices = const [0, 1, 2, 3, 4, 5, 6],
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<int> visibleIndices;

  static const destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Panel'),
    NavigationDestination(
      icon: Icon(Icons.location_city_outlined),
      label: 'Alanlar',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outline),
      label: 'Müşteriler',
    ),
    NavigationDestination(
      icon: Icon(Icons.description_outlined),
      label: 'Sözleştirmeler',
    ),
    NavigationDestination(icon: Icon(Icons.history), label: 'Bitenler'),
    NavigationDestination(
      icon: Icon(Icons.notifications_outlined),
      label: 'Bildirimler',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      label: 'Ayarlar',
    ),
    NavigationDestination(
      icon: Icon(Icons.bookmark_border),
      label: 'Rezervasyonlar',
    ),
  ];

  static const _labels = [
    'Ana Panel',
    'Reklam Alanları',
    'Müşteriler',
    'Sözleşmeler',
    'Biten Sözleşmeler',
    'Bildirimler',
    'Ayarlar',
    'Rezervasyonlar',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: 240,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
              child: Text(
                'RST DOLAPDERE',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            for (final index in visibleIndices)
              _SidebarItem(
                key: ValueKey(index),
                icon: (destinations[index].icon as Icon).icon!,
                label: _labels[index],
                selected: selectedIndex == index,
                onTap: () => onDestinationSelected(index),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = widget.selected;

    final borderColor = active
        ? const Color(0x6622D3EE)
        : Colors.white.withValues(alpha: _hovering ? 0.22 : 0.09);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0x2222D3EE)
              : Colors.white.withValues(alpha: _hovering ? 0.075 : 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: active ? 1.2 : 1),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF22D3EE).withValues(alpha: 0.12),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              if (_hovering || active)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: _hovering ? 1.5 : 1.2,
                        colors: [
                          const Color(
                            0xFF22D3EE,
                          ).withValues(alpha: active ? 0.12 : 0.08),
                          const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: active ? 0.07 : 0.04),
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
                  splashColor: const Color(0xFF22D3EE).withValues(alpha: 0.12),
                  highlightColor: Colors.white.withValues(alpha: 0.04),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.icon,
                          size: 21,
                          color: active
                              ? const Color(0xFF22D3EE)
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            widget.label,
                            style: TextStyle(
                              color: active
                                  ? colors.onSurface
                                  : colors.onSurface.withValues(alpha: 0.86),
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (active)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22D3EE),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF22D3EE),
                                  blurRadius: 7,
                                  spreadRadius: 1,
                                ),
                              ],
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
