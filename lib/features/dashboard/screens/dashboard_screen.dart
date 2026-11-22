import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/app_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_helper.dart';
import '../../../models/contract_model.dart';

enum DashboardDestination {
  adSpaces,
  activeContracts,
  availableAdSpaces,
  expiringContracts,
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.store, this.onNavigate});

  final AppStore store;
  final ValueChanged<DashboardDestination>? onNavigate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final expiring = store.expiringContracts;
        final horizontalPadding = MediaQuery.sizeOf(context).width < 600
            ? 16.0
            : 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Genel Bakış',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'RST Dolapdere reklam alanları yönetim paneline hoş geldiniz.',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),

              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 900
                      ? 4
                      : constraints.maxWidth > 550
                      ? 2
                      : 1;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: crossAxisCount == 1 ? 2.4 : 1.7,
                    children: [
                      _SummaryCard(
                        title: 'Toplam Reklam Alanı',
                        value: '${store.adSpaces.length}',
                        icon: Icons.dashboard_outlined,
                        color: AppColors.primary,
                        onTap: () =>
                            onNavigate?.call(DashboardDestination.adSpaces),
                      ),
                      _SummaryCard(
                        title: 'Aktif Sözleşmeler',
                        value: '${store.activeContracts.length}',
                        icon: Icons.description_outlined,
                        color: AppColors.success,
                        onTap: () => onNavigate?.call(
                          DashboardDestination.activeContracts,
                        ),
                      ),
                      _SummaryCard(
                        title: 'Boş Reklam Alanları',
                        value:
                            '${store.adSpaces.where((space) => space.isAvailable).length}',
                        icon: Icons.event_available_outlined,
                        color: AppColors.warning,
                        onTap: () => onNavigate?.call(
                          DashboardDestination.availableAdSpaces,
                        ),
                      ),
                      _SummaryCard(
                        title: 'Süresi Yaklaşan',
                        value: '${expiring.length}',
                        icon: Icons.notifications_active_outlined,
                        color: AppColors.danger,
                        onTap: () => onNavigate?.call(
                          DashboardDestination.expiringContracts,
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 30),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Süresi Yaklaşan Sözleşmeler',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (expiring.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.event_note_outlined,
                                  size: 42,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '10 gün içinde bitecek sözleşme bulunmuyor.',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...expiring.map(
                          (contract) => _ExpiringContract(
                            store: store,
                            contract: contract,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpiringContract extends StatelessWidget {
  const _ExpiringContract({required this.store, required this.contract});

  final AppStore store;
  final ContractModel contract;

  @override
  Widget build(BuildContext context) {
    final customer = store.customerFor(contract.customerId);
    final space = store.adSpaceFor(contract.adSpaceId);
    final days = DateHelper.daysUntil(contract.endDate);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.notifications_active_outlined,
        color: AppColors.danger,
      ),
      title: Text(space?.name ?? 'Reklam alanı'),
      subtitle: Text(
        '${customer?.name ?? 'Müşteri'} • ${DateFormat('dd.MM.yyyy').format(contract.endDate)}',
      ),
      trailing: Text(
        days == 0 ? 'Bugün' : '$days gün',
        style: const TextStyle(
          color: AppColors.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovering = value),
        hoverColor: Colors.transparent, // ani renk değişimini kapat
        highlightColor: Colors.transparent,
        splashColor: widget.color.withValues(alpha: 0.12),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _hovering ? 1 : 0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) {
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  // 1.5 = köşeleri de kapsayacak kadar büyük yarıçap
                  radius: t * 1.5,
                  colors: [
                    widget.color.withValues(alpha: 0.10),
                    widget.color.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.98, 1.0],
                ),
              ),
              child: child,
            );
          },
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final valueAndTitle = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

        if (constraints.maxWidth < 360) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.color, size: 28),
                const SizedBox(width: 14),
                Expanded(child: valueAndTitle),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(widget.icon, color: widget.color, size: 28),
              valueAndTitle,
            ],
          ),
        );
      },
    );
  }
}
