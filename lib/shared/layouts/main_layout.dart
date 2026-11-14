import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/app_store.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/notifications/screens/notification_screen.dart';
import '../../features/records/management_screens.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../models/app_user.dart';
import '../widgets/app_sidebar.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({
    super.key,
    required this.store,
    this.user,
    this.authService,
  });

  final AppStore store;
  final AppUser? user;
  final AuthService? authService;

  @override
  State<MainLayout> createState() => MainLayoutState();
}

class MainLayoutState extends State<MainLayout> {
  int selectedIndex = 0;
  ContractListFilter _contractFilter = ContractListFilter.all;
  AdSpaceListFilter _adSpaceFilter = AdSpaceListFilter.all;

  final List<String> pageTitles = [
    'Ana Panel',
    'Reklam Alanları',
    'Müşteriler',
    'Sözleşmeler',
    'Biten Sözleşmeler',
    'Bildirimler',
    'Ayarlar',
  ];

  bool _canAccess(String module) => widget.user?.canAccess(module) ?? true;

  List<int> get _visibleIndices => [
    if (_canAccess('dashboard')) 0,
    if (_canAccess('adSpaces')) 1,
    if (_canAccess('customers')) 2,
    if (_canAccess('contracts')) ...[3, 4],
    if (_canAccess('notifications')) 5,
    if (_canAccess('settings')) 6,
  ];

  @override
  void initState() {
    super.initState();
    if (!_canAccess('dashboard') && _visibleIndices.isNotEmpty) {
      selectedIndex = _visibleIndices.first;
    }
  }

  Widget getSelectedPage() {
    final module = switch (selectedIndex) {
      0 => 'dashboard',
      1 => 'adSpaces',
      2 => 'customers',
      3 || 4 => 'contracts',
      5 => 'notifications',
      6 => 'settings',
      _ => null,
    };
    if (module != null && !_canAccess(module)) {
      return const Center(child: Text('Bu bölümü görüntüleme yetkiniz yok.'));
    }
    switch (selectedIndex) {
      case 0:
        return DashboardScreen(
          store: widget.store,
          onNavigate: _canAccess('dashboard') ? _navigateFromDashboard : null,
        );
      case 1:
        return ManagementScreen(
          store: widget.store,
          type: RecordType.adSpaces,
          initialAdSpaceFilter: _adSpaceFilter,
          authService: widget.authService,
        );
      case 2:
        return ManagementScreen(
          store: widget.store,
          type: RecordType.customers,
          authService: widget.authService,
        );
      case 3:
        return ManagementScreen(
          store: widget.store,
          type: RecordType.contracts,
          initialContractFilter: _contractFilter,
          authService: widget.authService,
        );
      case 4:
        return ManagementScreen(
          store: widget.store,
          type: RecordType.contracts,
          showEndedContracts: true,
          authService: widget.authService,
        );
      case 5:
        return NotificationScreen(
          store: widget.store,
          onReviewContract: openContract,
        );
      case 6:
        return SettingsScreen(
          store: widget.store,
          user: widget.user,
          authService: widget.authService,
        );

      default:
        return Center(
          child: Text(
            '${pageTitles[selectedIndex]} ekranını sonraki aşamada hazırlayacağız.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        );
    }
  }

  void _selectPage(int index) {
    setState(() {
      selectedIndex = index;
      _contractFilter = ContractListFilter.all;
      _adSpaceFilter = AdSpaceListFilter.all;
    });
  }

  void _navigateFromDashboard(DashboardDestination destination) {
    final requiredModule = switch (destination) {
      DashboardDestination.adSpaces ||
      DashboardDestination.availableAdSpaces => 'adSpaces',
      DashboardDestination.activeContracts ||
      DashboardDestination.expiringContracts => 'contracts',
    };
    if (!_canAccess(requiredModule)) return;
    setState(() {
      switch (destination) {
        case DashboardDestination.adSpaces:
          selectedIndex = 1;
          _adSpaceFilter = AdSpaceListFilter.all;
        case DashboardDestination.activeContracts:
          selectedIndex = 3;
          _contractFilter = ContractListFilter.active;
        case DashboardDestination.availableAdSpaces:
          selectedIndex = 1;
          _adSpaceFilter = AdSpaceListFilter.available;
        case DashboardDestination.expiringContracts:
          selectedIndex = 3;
          _contractFilter = ContractListFilter.upcoming;
      }
    });
  }

  void openContract(String contractId) {
    if (!_canAccess('contracts')) return;
    final contract = widget.store.contracts.where(
      (item) => item.id == contractId,
    );
    if (contract.isEmpty) return;
    final record = contract.first;
    final customer = widget.store.customerFor(record.customerId);
    final space = widget.store.adSpaceFor(record.adSpaceId);
    setState(() {
      selectedIndex = 3;
      _contractFilter = ContractListFilter.all;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(space?.name ?? 'Sözleşme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kiracı: ${customer?.name ?? 'Bilinmiyor'}'),
              Text(
                'Başlangıç: ${DateFormat('dd.MM.yyyy').format(record.startDate)}',
              ),
              Text('Bitiş: ${DateFormat('dd.MM.yyyy').format(record.endDate)}'),
              Text(
                'Aylık bedel: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(record.monthlyPrice)}',
              ),
              if (record.isFinalized)
                const Text('Durum: Bitti olarak işaretlendi'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final visibleIndices = _visibleIndices.isEmpty ? [0] : _visibleIndices;
        final selectedVisibleIndex = visibleIndices.indexOf(selectedIndex);

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (isDesktop)
                  AppSidebar(
                    selectedIndex: selectedIndex,
                    visibleIndices: visibleIndices,
                    onDestinationSelected: _selectPage,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 72,
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 24 : 16,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            bottom: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pageTitles[selectedIndex],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.account_circle_outlined,
                              color: AppColors.textSecondary,
                              size: 28,
                            ),
                            if (isDesktop) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'Yönetici',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(child: getSelectedPage()),
                    ],
                  ),
                ),
              ],
            ),
          ),

          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: selectedVisibleIndex < 0
                      ? 0
                      : selectedVisibleIndex,
                  onDestinationSelected: (index) =>
                      _selectPage(visibleIndices[index]),
                  destinations: visibleIndices
                      .map((index) => AppSidebar.destinations[index])
                      .toList(),
                ),
        );
      },
    );
  }
}
