import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../../core/services/app_store.dart';
import '../../core/utils/window_focus_helper.dart';
import '../../features/notifications/services/reminder_service.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/notifications/screens/notification_screen.dart';
import '../../features/records/management_screens.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../widgets/app_sidebar.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key, required this.store});

  final AppStore store;

  @override
  State<MainLayout> createState() => MainLayoutState();
}

class MainLayoutState extends State<MainLayout> {
  int selectedIndex = 0;
  ContractListFilter _contractFilter = ContractListFilter.all;
  AdSpaceListFilter _adSpaceFilter = AdSpaceListFilter.all;
  String? _pendingContractId;

  final List<String> pageTitles = [
    'Ana Panel',
    'Reklam Alanları',
    'Müşteriler',
    'Sözleşmeler',
    'Biten Sözleşmeler',
    'Bildirimler',
    'Ayarlar',
  ];

  bool _canAccess(String module) => true;

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
    ReminderService.instance.setNotificationHandler(
      _handleNotificationResponse,
    );
    widget.store.addListener(_onStoreChanged);
  }

  void initializeReminders() {
    unawaited(_initializeReminders());
  }

  Future<void> _initializeReminders() async {
    try {
      await ReminderService.instance.initialize();
      await ReminderService.instance.sync(widget.store);
    } catch (error) {
      debugPrint('Masaüstü bildirimleri başlatılamadı: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Masaüstü bildirimleri başlatılamadı: $error'),
          ),
        );
      }
    }
  }

  Timer? _reminderDebounce;

  void _onStoreChanged() {
    final pendingContractId = _pendingContractId;
    if (pendingContractId != null &&
        widget.store.contracts.any(
          (contract) => contract.id == pendingContractId,
        )) {
      _pendingContractId = null;
      openContract(pendingContractId);
    }
    // Art arda yapılan işlemlerde bildirimler her seferinde yeniden kurulmaz;
    // son değişiklikten 2 sn sonra bir kez kurulur.
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted) unawaited(_syncReminders());
    });
  }

  Future<void> _syncReminders() async {
    try {
      await ReminderService.instance.sync(widget.store);
    } catch (error) {
      debugPrint('Masaüstü bildirimleri eşitlenemedi: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Masaüstü bildirimleri eşitlenemedi: $error')),
        );
      }
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    WindowFocusHelper.bringToFront(); // <-- Pencereyi öne getirir ve simgeden çıkarır
    final action = response.actionId ?? '';
    if (action == 'snooze' || action.startsWith('snooze:')) {
      final contractId = action.startsWith('snooze:')
          ? action.substring('snooze:'.length)
          : response.payload;
      if (contractId != null && contractId.isNotEmpty) {
        unawaited(_chooseSnoozeDuration(contractId));
      }
      return;
    }
    if (action == 'expiring' || action.startsWith('expiring:')) {
      openExpiringContracts();
      return;
    }
    if (action.startsWith('contract:')) {
      _openNotifiedContract(action.substring('contract:'.length));
      return;
    }
    final contractId = response.payload;
    if (contractId != null && contractId.isNotEmpty) {
      _openNotifiedContract(contractId);
    }
  }

  Future<void> _chooseSnoozeDuration(String contractId) async {
    final duration = await showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hatırlatmayı ertele'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, duration) in const [
                ('5 dakika', Duration(minutes: 5)),
                ('10 dakika', Duration(minutes: 10)),
                ('30 dakika', Duration(minutes: 30)),
                ('1 saat', Duration(hours: 1)),
                ('2 saat', Duration(hours: 2)),
                ('1 gün', Duration(days: 1)),
                ('2 gün', Duration(days: 2)),
              ])
                ListTile(
                  title: Text(label),
                  leading: const Icon(Icons.snooze_outlined),
                  onTap: () => Navigator.of(context).pop(duration),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
    if (duration == null || !mounted) return;
    try {
      final contracts = widget.store.contracts.where(
        (item) => item.id == contractId,
      );
      if (contracts.isEmpty) {
        throw StateError('Sözleşme bulunamadı.');
      }
      final contract = contracts.first;
      await ReminderService.instance.snooze(
        contractId,
        duration,
        widget.store.workingDays,
        contract.endDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hatırlatma ${_snoozeDurationLabel(duration)} ertelendi.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hatırlatma ertelenemedi: $error')),
        );
      }
    }
  }

  String _snoozeDurationLabel(Duration duration) {
    if (duration.inDays > 0) return '${duration.inDays} gün';
    if (duration.inHours > 0) return '${duration.inHours} saat';
    return '${duration.inMinutes} dakika';
  }

  void _openNotifiedContract(String contractId) {
    if (!_canAccess('contracts')) return;
    if (!widget.store.contracts.any((contract) => contract.id == contractId)) {
      _pendingContractId = contractId;
      return;
    }
    openContract(contractId);
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
        );
      case 2:
        return ManagementScreen(
          store: widget.store,
          type: RecordType.customers,
        );
      case 3:
        return ManagementScreen(
          key: ValueKey('contracts-${_contractFilter.name}'),
          store: widget.store,
          type: RecordType.contracts,
          initialContractFilter: _contractFilter,
        );
      case 4:
        return ManagementScreen(
          key: ValueKey('ended-contracts-${_contractFilter.name}'),
          store: widget.store,
          type: RecordType.contracts,
          showEndedContracts: true,
        );
      case 5:
        return NotificationScreen(
          store: widget.store,
          onReviewContract: openContract,
        );
      case 6:
        return SettingsScreen(store: widget.store);

      default:
        return Center(
          child: Text(
            '${pageTitles[selectedIndex]} ekranını sonraki aşamada hazırlayacağız.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                'Toplam tutar: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(record.monthlyPrice)}',
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

  void openExpiringContracts() {
    if (!_canAccess('contracts')) return;
    setState(() {
      selectedIndex = 3;
      _contractFilter = ContractListFilter.upcoming;
    });
  }

  @override
  void dispose() {
    _reminderDebounce?.cancel();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
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
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pageTitles[selectedIndex],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.account_circle_outlined,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              size: 28,
                            ),
                            if (isDesktop) ...[
                              const SizedBox(width: 8),
                              Text(
                                'Yönetici',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
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
