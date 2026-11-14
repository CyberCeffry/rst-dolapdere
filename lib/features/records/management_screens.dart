import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/services/app_store.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/contract_date_helper.dart';
import '../../core/utils/contract_remaining_time.dart';
import '../../core/utils/date_helper.dart';
import '../contracts/services/contract_pdf_service.dart';
import 'services/ad_space_pdf_service.dart';
import '../../models/ad_space_model.dart';
import '../../models/app_user.dart';
import '../../models/contract_history_entry.dart';
import '../../models/contract_model.dart';
import '../../models/customer_model.dart';

enum RecordType { adSpaces, customers, contracts }

enum ContractListFilter { all, active, upcoming, expired }

enum AdSpaceListFilter { all, available, occupied }

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({
    super.key,
    required this.store,
    required this.type,
    this.showEndedContracts = false,
    this.initialContractFilter = ContractListFilter.all,
    this.initialAdSpaceFilter = AdSpaceListFilter.all,
    this.authService,
  });

  final AppStore store;
  final RecordType type;
  final bool showEndedContracts;
  final ContractListFilter initialContractFilter;
  final AdSpaceListFilter initialAdSpaceFilter;
  final AuthService? authService;

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  late ContractListFilter _contractFilter;
  late AdSpaceListFilter _adSpaceFilter;
  bool _nearestFirst = true;
  bool _loadingAvailableContracts = false;
  String? _availableContractsError;
  List<ContractModel> _availableContracts = [];
  final Map<String, String> _availableCustomerNames = {};
  final Map<String, String> _availableAdSpaceNames = {};

  @override
  void initState() {
    super.initState();
    _contractFilter = widget.initialContractFilter;
    _adSpaceFilter = widget.initialAdSpaceFilter;
    if (widget.type == RecordType.contracts &&
        !widget.showEndedContracts &&
        widget.store.currentUser?.role == AppRole.supervisor &&
        widget.authService != null) {
      _loadAvailableContracts();
    }
  }

  String get _title => switch (widget.type) {
    RecordType.adSpaces => 'Reklam Alanları',
    RecordType.customers => 'Müşteriler',
    RecordType.contracts => 'Sözleşmeler',
  };

  List<dynamic> get _records {
    final records = switch (widget.type) {
      RecordType.adSpaces => _adSpaceRecords(),
      RecordType.customers => widget.store.customers,
      RecordType.contracts => _contractRecords(),
    };
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return records;
    return records
        .where((record) => _searchText(record).contains(query))
        .toList();
  }

  List<AdSpaceModel> _adSpaceRecords() => widget.store.adSpaces.where((space) {
    final occupied = widget.store.activeContractForAdSpace(space.id) != null;
    return switch (_adSpaceFilter) {
      AdSpaceListFilter.all => true,
      AdSpaceListFilter.available => !occupied,
      AdSpaceListFilter.occupied => occupied,
    };
  }).toList();

  List<ContractModel> _contractRecords() {
    final storedContracts = widget.showEndedContracts
        ? widget.store.endedContracts
        : widget.store.contracts
              .where((contract) => !contract.isFinalized)
              .toList();
    final contracts = widget.showEndedContracts
        ? storedContracts
        : [
            ...storedContracts,
            ..._availableContracts.where(
              (available) =>
                  !storedContracts.any((stored) => stored.id == available.id),
            ),
          ];
    if (widget.showEndedContracts) return contracts;
    final filtered = contracts.where((contract) {
      final days = DateHelper.daysUntil(contract.endDate);
      return switch (_contractFilter) {
        ContractListFilter.all => true,
        ContractListFilter.active =>
          widget.store.activeContracts.any(
                (active) => active.id == contract.id,
              ) ||
              (contract.isActive &&
                  !contract.isFinalized &&
                  DateHelper.daysUntil(contract.startDate) <= 0 &&
                  DateHelper.daysUntil(contract.endDate) >= 0),
        ContractListFilter.upcoming => days >= 0 && days <= 10,
        ContractListFilter.expired => days < 0,
      };
    }).toList();
    filtered.sort((a, b) {
      final comparison = a.endDate.compareTo(b.endDate);
      return _nearestFirst ? comparison : -comparison;
    });
    return filtered;
  }

  Future<void> _loadAvailableContracts() async {
    final service = widget.authService;
    if (service == null) return;
    setState(() {
      _loadingAvailableContracts = true;
      _availableContractsError = null;
    });
    try {
      final values = await service.listAvailableContracts();
      if (!mounted) return;
      setState(() {
        _availableContracts = values
            .map((value) => ContractModel.fromJson(value))
            .toList();
        _availableCustomerNames
          ..clear()
          ..addEntries(
            values.map(
              (value) => MapEntry(
                value['id'] as String,
                value['customerName'] as String? ?? 'Kiracı',
              ),
            ),
          );
        _availableAdSpaceNames
          ..clear()
          ..addEntries(
            values.map(
              (value) => MapEntry(
                value['id'] as String,
                value['adSpaceName'] as String? ?? 'Reklam alanı',
              ),
            ),
          );
      });
    } catch (error) {
      if (mounted) setState(() => _availableContractsError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingAvailableContracts = false);
    }
  }

  String _searchText(dynamic record) {
    if (record is AdSpaceModel) {
      return '${record.name} ${record.location}'.toLowerCase();
    }
    if (record is CustomerModel) {
      return '${record.name} ${record.company} ${record.phone}'.toLowerCase();
    }
    final contract = record as ContractModel;
    final customer = widget.store.customerFor(contract.customerId);
    final space = widget.store.adSpaceFor(contract.adSpaceId);
    return '${customer?.name ?? _availableCustomerNames[contract.id] ?? ''} '
            '${space?.name ?? _availableAdSpaceNames[contract.id] ?? ''}'
        .toLowerCase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _edit(dynamic record, {bool isRenewal = false}) async {
    if (record is ContractModel &&
        !isRenewal &&
        (record.isFinalized || DateHelper.daysUntil(record.endDate) < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biten sözleşme düzenlenemez; uzatabilirsiniz.'),
        ),
      );
      return;
    }
    if (widget.type == RecordType.contracts &&
        (widget.store.customers.isEmpty || widget.store.adSpaces.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce en az bir müşteri ve reklam alanı ekleyin.'),
        ),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _RecordFormDialog(
        store: widget.store,
        type: widget.type,
        initial: record,
        isRenewal: isRenewal,
      ),
    );
    if (saved == true && mounted) {
      final isSupervisor = widget.store.currentUser?.role == AppRole.supervisor;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSupervisor
                ? 'Sözleşme talebi yönetici onayına gönderildi.'
                : record == null
                ? 'Kayıt eklendi.'
                : 'Kayıt güncellendi.',
          ),
        ),
      );
    }
  }

  Future<void> _markContractEnded(ContractModel contract) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sözleşmeyi bitir'),
        content: const Text(
          'Sözleşme kalıcı olarak bitenler listesine alınır. Daha sonra yeniden açılamaz; devam etmek ister misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.markContractEnded(contract.id);
  }

  Future<void> _renewContract(ContractModel contract) =>
      _edit(contract, isRenewal: true);

  Future<void> _showContractDetails(ContractModel contract) => showDialog<void>(
    context: context,
    builder: (context) =>
        _ContractDetailsDialog(store: widget.store, contract: contract),
  );

  Future<void> _showCustomerDetails(CustomerModel customer) => showDialog<void>(
    context: context,
    builder: (context) =>
        _CustomerDetailsDialog(store: widget.store, customer: customer),
  );

  Future<void> _assignResponsible(ContractModel contract) async {
    final service = widget.authService;
    if (service == null) return;
    final user = widget.store.currentUser;
    final userId = user?.role == AppRole.supervisor
        ? user!.uid
        : await showDialog<String>(
            context: context,
            builder: (context) => _AssignResponsibleDialog(
              authService: service,
              currentUserId: user?.uid,
            ),
          );
    if (userId == null) return;
    try {
      await service.assignContract(
        contractId: contract.id,
        responsibleUserId: userId,
      );
      if (user?.role == AppRole.supervisor) {
        setState(() {
          _availableContracts.removeWhere((item) => item.id == contract.id);
        });
        await _loadAvailableContracts();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sorumlu atanamadı: $error')));
      }
    }
  }

  Future<void> _toggleContractActive(ContractModel contract) async {
    try {
      await widget.store.setContractActive(contract.id, !contract.isActive);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sözleşme durumu değiştirilemedi: $error')),
        );
      }
    }
  }

  Future<void> _exportContracts(List<dynamic> records) async {
    try {
      await ContractPdfService.exportContracts(
        widget.store,
        records.whereType<ContractModel>().toList(),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF oluşturulamadı: $error')));
      }
    }
  }

  Future<void> _exportAdSpaces(List<dynamic> records) async {
    try {
      await AdSpacePdfService.exportAdSpaces(
        widget.store,
        records.whereType<AdSpaceModel>().toList(),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF oluşturulamadı: $error')));
      }
    }
  }

  Future<void> _delete(dynamic record) async {
    final title = _recordTitle(record);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kaydı sil'),
        content: Text('$title kaydını silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (record is AdSpaceModel) {
        await widget.store.deleteAdSpace(record.id);
      } else if (record is CustomerModel) {
        await widget.store.deleteCustomer(record.id);
      } else {
        await widget.store.deleteContract((record as ContractModel).id);
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  String _recordTitle(dynamic record) {
    if (record is AdSpaceModel) return record.name;
    if (record is CustomerModel) return record.name;
    final contract = record as ContractModel;
    return widget.store.adSpaceFor(contract.adSpaceId)?.name ?? 'Sözleşme';
  }

  Widget _recordTile(dynamic record) {
    String title;
    String subtitle;
    Widget? subtitleWidget;
    IconData icon;
    Color statusColor = AppColors.textSecondary;
    String? status;

    if (record is AdSpaceModel) {
      final contract = widget.store.activeContractForAdSpace(record.id);
      final customer = contract == null
          ? null
          : widget.store.customerFor(contract.customerId);
      final days = contract == null
          ? null
          : ContractRemainingTime.daysUntil(contract.endDate);
      title = record.name;
      subtitle = contract == null ? 'Kiracı yok' : '';
      if (contract != null) {
        final remainingStyle =
            days != null && ContractRemainingTime.isUrgent(days)
            ? const TextStyle(color: AppColors.danger)
            : null;
        subtitleWidget = Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Kiracı: ${customer?.name ?? 'Bilinmiyor'}\n'),
              TextSpan(
                text:
                    'Bitiş: ${DateFormat('dd.MM.yyyy').format(contract.endDate)}\n',
              ),
              const TextSpan(text: 'Kalan süre: '),
              TextSpan(
                text: ContractRemainingTime.format(days!),
                style: remainingStyle,
              ),
            ],
          ),
        );
      }
      icon = Icons.location_city_outlined;
      status = contract == null ? 'Boş' : 'Kirada';
      statusColor = contract == null ? AppColors.success : AppColors.primary;
      if (days != null && ContractRemainingTime.isUrgent(days)) {
        statusColor = AppColors.danger;
      }
    } else if (record is CustomerModel) {
      title = record.name;
      subtitle = [
        record.company,
        record.phone,
        record.email,
      ].where((part) => part.isNotEmpty).join(' • ');
      icon = Icons.person_outline;
      final activeCount = widget.store.activeContracts
          .where((contract) => contract.customerId == record.id)
          .length;
      status = '$activeCount aktif alan';
    } else {
      final contract = record as ContractModel;
      final customer = widget.store.customerFor(contract.customerId);
      final space = widget.store.adSpaceFor(contract.adSpaceId);
      final days = DateHelper.daysUntil(contract.endDate);
      title =
          space?.name ?? _availableAdSpaceNames[contract.id] ?? 'Reklam alanı';
      subtitle =
          '${customer?.name ?? _availableCustomerNames[contract.id] ?? 'Kiracı'} • '
          '${DateFormat('dd.MM.yyyy').format(contract.startDate)} - '
          '${DateFormat('dd.MM.yyyy').format(contract.endDate)} • '
          '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(contract.monthlyPrice)} / ay'
          '${contract.responsibleUsername == null ? '' : ' • Sorumlu: ${contract.responsibleUsername}'}';
      icon = Icons.description_outlined;
      status = contract.isFinalized
          ? 'Bitti olarak işaretlendi'
          : days < 0
          ? 'Süresi doldu'
          : days <= 10
          ? '$days gün kaldı'
          : 'Aktif';
      statusColor = contract.isFinalized || days < 0
          ? AppColors.textSecondary
          : days <= 10
          ? AppColors.danger
          : AppColors.success;
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.background,
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child:
              subtitleWidget ??
              Text(subtitle.isEmpty ? 'Ek bilgi bulunmuyor' : subtitle),
        ),
        trailing: SizedBox(
          width: 130,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  status,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Kayıt işlemleri',
                onSelected: (value) {
                  if (record is ContractModel) {
                    switch (value) {
                      case 'details':
                        _showContractDetails(record);
                      case 'toggle':
                        _toggleContractActive(record);
                      case 'assign_self':
                        _assignResponsible(record);
                      case 'edit':
                        _edit(record);
                      case 'end':
                        _markContractEnded(record);
                      case 'renew':
                        _renewContract(record);
                      case 'delete':
                        _delete(record);
                      case 'assign':
                        _assignResponsible(record);
                    }
                  } else if (record is CustomerModel && value == 'details') {
                    _showCustomerDetails(record);
                  } else if (value == 'edit') {
                    _edit(record);
                  } else {
                    _delete(record);
                  }
                },
                itemBuilder: (context) {
                  final supervisor =
                      widget.store.currentUser?.role == AppRole.supervisor;
                  if (record is ContractModel) {
                    final ended =
                        record.isFinalized ||
                        DateHelper.daysUntil(record.endDate) < 0;
                    final supervisor =
                        widget.store.currentUser?.role == AppRole.supervisor;
                    return [
                      const PopupMenuItem(
                        value: 'details',
                        child: Text('Detayları görüntüle'),
                      ),
                      if (supervisor &&
                          record.responsibleUserId ==
                              widget.store.currentUser?.uid)
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            record.isActive ? 'Pasife al' : 'Etkinleştir',
                          ),
                        ),
                      if (supervisor && record.responsibleUserId == null)
                        const PopupMenuItem(
                          value: 'assign_self',
                          child: Text('Kendime ata'),
                        ),
                      if (!supervisor && !ended)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Düzenle'),
                        ),
                      if (!supervisor && !record.isFinalized)
                        const PopupMenuItem(
                          value: 'end',
                          child: Text('Bitti olarak işaretle'),
                        ),
                      const PopupMenuItem(
                        value: 'renew',
                        child: Text('Sözleşmeyi uzat'),
                      ),
                      if (!supervisor &&
                          (widget.store.currentUser?.role == AppRole.admin ||
                              widget.store.currentUser?.role ==
                                  AppRole.manager))
                        const PopupMenuItem(
                          value: 'assign',
                          child: Text('Sorumlu ata'),
                        ),
                      if (!supervisor)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Sil'),
                        ),
                    ];
                  }
                  if (supervisor && record is AdSpaceModel) {
                    return const [];
                  }
                  if (supervisor && record is CustomerModel) {
                    return const [
                      PopupMenuItem(
                        value: 'details',
                        child: Text('Detayları görüntüle'),
                      ),
                    ];
                  }
                  return [
                    if (record is CustomerModel)
                      const PopupMenuItem(
                        value: 'details',
                        child: Text('Detayları görüntüle'),
                      ),
                    const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                    const PopupMenuItem(value: 'delete', child: Text('Sil')),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final records = _records;
        final contracts = widget.type == RecordType.contracts;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.showEndedContracts ? 'Biten Sözleşmeler' : _title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!widget.showEndedContracts &&
                      !(widget.store.currentUser?.role == AppRole.supervisor &&
                          widget.type != RecordType.contracts))
                    FilledButton.icon(
                      onPressed: () => _edit(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Ekle'),
                    ),
                  if (contracts || widget.type == RecordType.adSpaces)
                    IconButton(
                      tooltip: contracts
                          ? 'Görünen sözleşmeleri PDF dışa aktar'
                          : 'Görünen reklam alanlarını PDF dışa aktar',
                      onPressed: () => contracts
                          ? _exportContracts(records)
                          : _exportAdSpaces(records),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                ],
              ),
              if (contracts && !widget.showEndedContracts) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width < 400
                            ? MediaQuery.sizeOf(context).width - 72
                            : 260,
                      ),
                      child: DropdownButtonFormField<ContractListFilter>(
                        initialValue: _contractFilter,
                        decoration: const InputDecoration(labelText: 'Filtre'),
                        items: const [
                          DropdownMenuItem(
                            value: ContractListFilter.all,
                            child: Text('Tüm sözleşmeler'),
                          ),
                          DropdownMenuItem(
                            value: ContractListFilter.active,
                            child: Text('Aktif sözleşmeler'),
                          ),
                          DropdownMenuItem(
                            value: ContractListFilter.upcoming,
                            child: Text('Yaklaşan sözleşmeler'),
                          ),
                          DropdownMenuItem(
                            value: ContractListFilter.expired,
                            child: Text('Süresi dolanlar'),
                          ),
                        ],
                        selectedItemBuilder: (context) => const [
                          Text('Tümü', overflow: TextOverflow.ellipsis),
                          Text('Aktif', overflow: TextOverflow.ellipsis),
                          Text('Yaklaşan', overflow: TextOverflow.ellipsis),
                          Text('Süresi dolan', overflow: TextOverflow.ellipsis),
                        ],
                        onChanged: (value) => setState(
                          () =>
                              _contractFilter = value ?? ContractListFilter.all,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _nearestFirst = !_nearestFirst),
                      icon: Icon(
                        _nearestFirst
                            ? Icons.south_outlined
                            : Icons.north_outlined,
                      ),
                      label: Text(
                        _nearestFirst ? 'Yakın tarih önce' : 'Uzak tarih önce',
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.type == RecordType.adSpaces) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width < 400
                          ? MediaQuery.sizeOf(context).width - 72
                          : 260,
                    ),
                    child: DropdownButtonFormField<AdSpaceListFilter>(
                      initialValue: _adSpaceFilter,
                      decoration: const InputDecoration(labelText: 'Filtre'),
                      items: const [
                        DropdownMenuItem(
                          value: AdSpaceListFilter.all,
                          child: Text('Tüm reklam alanları'),
                        ),
                        DropdownMenuItem(
                          value: AdSpaceListFilter.available,
                          child: Text('Boş'),
                        ),
                        DropdownMenuItem(
                          value: AdSpaceListFilter.occupied,
                          child: Text('Kirada'),
                        ),
                      ],
                      selectedItemBuilder: (context) => const [
                        Text('Tümü', overflow: TextOverflow.ellipsis),
                        Text('Boş', overflow: TextOverflow.ellipsis),
                        Text('Kirada', overflow: TextOverflow.ellipsis),
                      ],
                      onChanged: (value) => setState(
                        () => _adSpaceFilter = value ?? AdSpaceListFilter.all,
                      ),
                    ),
                  ),
                ),
              ],
              if (contracts &&
                  !widget.showEndedContracts &&
                  widget.store.currentUser?.role == AppRole.supervisor) ...[
                if (_loadingAvailableContracts) const LinearProgressIndicator(),
                if (_availableContractsError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Boşta sözleşmeler yüklenemedi: $_availableContractsError',
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                if (_availableContracts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_availableContracts.length} sözleşme kendinize atanabilir.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Ara',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              if (records.isEmpty)
                Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            widget.type == RecordType.adSpaces
                                ? Icons.location_city_outlined
                                : widget.type == RecordType.customers
                                ? Icons.people_outline
                                : Icons.description_outlined,
                            size: 40,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'Henüz kayıt bulunmuyor.'
                                : 'Aramanızla eşleşen kayıt yok.',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ...records.map(_recordTile),
            ],
          ),
        );
      },
    );
  }
}

class _AssignResponsibleDialog extends StatefulWidget {
  const _AssignResponsibleDialog({
    required this.authService,
    this.currentUserId,
  });

  final AuthService authService;
  final String? currentUserId;

  @override
  State<_AssignResponsibleDialog> createState() =>
      _AssignResponsibleDialogState();
}

class _AssignResponsibleDialogState extends State<_AssignResponsibleDialog> {
  String? _selectedUserId;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sözleşme sorumlusu'),
    content: SizedBox(
      width: 380,
      child: StreamBuilder<List<AppUser>>(
        stream: widget.authService.watchUsers(),
        builder: (context, snapshot) {
          final users = (snapshot.data ?? const <AppUser>[])
              .where((user) => user.isActive)
              .toList();
          if (snapshot.hasError) {
            return Text('Kullanıcılar alınamadı: ${snapshot.error}');
          }
          if (users.isEmpty) return const Text('Etkin kullanıcı bulunamadı.');
          _selectedUserId ??=
              users
                  .where((user) => user.uid == widget.currentUserId)
                  .firstOrNull
                  ?.uid ??
              users.first.uid;
          return DropdownButtonFormField<String>(
            initialValue: _selectedUserId,
            decoration: const InputDecoration(labelText: 'Sorumlu kullanıcı'),
            items: users
                .map(
                  (user) => DropdownMenuItem(
                    value: user.uid,
                    child: Text('${user.username} (${user.role.name})'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedUserId = value),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: _selectedUserId == null
            ? null
            : () => Navigator.pop(context, _selectedUserId),
        child: const Text('Ata'),
      ),
    ],
  );
}

class _ContractDetailsDialog extends StatelessWidget {
  const _ContractDetailsDialog({required this.store, required this.contract});

  final AppStore store;
  final ContractModel contract;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final customer = store.customerFor(contract.customerId);
    final space = store.adSpaceFor(contract.adSpaceId);
    final history = [...contract.history]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final currencyFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    String actionLabel(ContractHistoryAction action) => switch (action) {
      ContractHistoryAction.created => 'Sözleşme eklendi',
      ContractHistoryAction.renewed => 'Sözleşme uzatıldı',
      ContractHistoryAction.ended => 'Sözleşme bitirildi',
      ContractHistoryAction.activated => 'Sözleşme etkinleştirildi',
      ContractHistoryAction.assigned => 'Sözleşme sorumlusu atandı',
    };

    return AlertDialog(
      title: Text(space?.name ?? 'Sözleşme detayı'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kiracı: ${customer?.name ?? 'Bilinmiyor'}'),
              Text('Alan: ${space?.name ?? 'Silinmiş reklam alanı'}'),
              Text('Başlangıç: ${dateFormat.format(contract.startDate)}'),
              Text('Bitiş: ${dateFormat.format(contract.endDate)}'),
              Text(
                'Aylık bedel: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(contract.monthlyPrice)}',
              ),
              if (contract.notes.isNotEmpty) Text('Notlar: ${contract.notes}'),
              const SizedBox(height: 20),
              Text(
                'Hareketler',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Text('Bu sözleşme için kayıtlı hareket bulunmuyor.'),
              ...history.map((entry) {
                final detail = switch (entry.action) {
                  ContractHistoryAction.created =>
                    entry.newEndDate == null
                        ? ''
                        : 'Bitiş: ${dateFormat.format(entry.newEndDate!)}'
                              '${entry.newMonthlyPrice == null ? '' : ' • Bedel: ${currencyFormat.format(entry.newMonthlyPrice)}'}',
                  ContractHistoryAction.renewed =>
                    '${entry.previousEndDate == null ? '-' : dateFormat.format(entry.previousEndDate!)} → '
                        '${entry.newEndDate == null ? '-' : dateFormat.format(entry.newEndDate!)}'
                        '${entry.previousMonthlyPrice == null || entry.newMonthlyPrice == null ? '' : ' • Bedel: ${currencyFormat.format(entry.previousMonthlyPrice)} → ${currencyFormat.format(entry.newMonthlyPrice)}'}',
                  ContractHistoryAction.ended =>
                    'Bitiş: ${dateFormat.format(entry.newEndDate ?? contract.endDate)}',
                  ContractHistoryAction.activated =>
                    'Bitiş: ${dateFormat.format(entry.newEndDate ?? contract.endDate)}',
                  ContractHistoryAction.assigned =>
                    'Sorumlu: ${entry.targetUsername ?? contract.responsibleUsername ?? '-'}',
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(actionLabel(entry.action)),
                  subtitle: Text(
                    '${dateFormat.format(entry.occurredAt)}'
                    '${entry.actorUsername == null ? '' : ' • İşlemi yapan: ${entry.actorUsername}'}'
                    '${detail.isEmpty ? '' : ' • $detail'}',
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class _CustomerDetailsDialog extends StatelessWidget {
  const _CustomerDetailsDialog({required this.store, required this.customer});

  final AppStore store;
  final CustomerModel customer;

  @override
  Widget build(BuildContext context) {
    final contracts =
        store.contracts
            .where((contract) => contract.customerId == customer.id)
            .toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final dateFormat = DateFormat('dd.MM.yyyy');

    return AlertDialog(
      title: Text(customer.name),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (customer.company.isNotEmpty)
                Text('Firma: ${customer.company}'),
              if (customer.phone.isNotEmpty) Text('Telefon: ${customer.phone}'),
              if (customer.email.isNotEmpty) Text('E-posta: ${customer.email}'),
              const SizedBox(height: 16),
              Text(
                'Kiralanan alanlar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (contracts.isEmpty)
                const Text('Bu kiracıya bağlı sözleşme bulunmuyor.'),
              ...contracts.map((contract) {
                final space = store.adSpaceFor(contract.adSpaceId);
                final ended =
                    contract.isFinalized ||
                    DateHelper.daysUntil(contract.endDate) < 0;
                final startsLater =
                    DateHelper.daysUntil(contract.startDate) > 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.location_city_outlined),
                  title: Text(space?.name ?? 'Silinmiş reklam alanı'),
                  subtitle: Text(
                    '${space?.location.isNotEmpty == true ? '${space!.location} • ' : ''}'
                    '${dateFormat.format(contract.startDate)} - ${dateFormat.format(contract.endDate)}',
                  ),
                  trailing: Text(
                    ended
                        ? 'Bitti'
                        : startsLater
                        ? 'Başlayacak'
                        : 'Aktif',
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class _RecordFormDialog extends StatefulWidget {
  const _RecordFormDialog({
    required this.store,
    required this.type,
    this.initial,
    this.isRenewal = false,
  });

  final AppStore store;
  final RecordType type;
  final dynamic initial;
  final bool isRenewal;

  @override
  State<_RecordFormDialog> createState() => _RecordFormDialogState();
}

class _RecordFormDialogState extends State<_RecordFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _notes;
  late final TextEditingController _durationCount;
  late String? _customerId;
  late String? _adSpaceId;
  late DateTime _startDate;
  late DateTime _endDate;
  late ContractDurationUnit _durationUnit;
  late bool _active;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(
      text: initial is AdSpaceModel
          ? initial.name
          : initial is CustomerModel
          ? initial.name
          : '',
    );
    _company = TextEditingController(
      text: initial is CustomerModel ? initial.company : '',
    );
    _phone = TextEditingController(
      text: initial is CustomerModel ? initial.phone : '',
    );
    _email = TextEditingController(
      text: initial is CustomerModel ? initial.email : '',
    );
    _location = TextEditingController(
      text: initial is AdSpaceModel ? initial.location : '',
    );
    _description = TextEditingController(
      text: initial is AdSpaceModel ? initial.description : '',
    );
    _price = TextEditingController(
      text: initial is AdSpaceModel
          ? (initial.monthlyPrice == 0 ? '' : initial.monthlyPrice.toString())
          : initial is ContractModel
          ? initial.monthlyPrice.toString()
          : '',
    );
    _notes = TextEditingController(
      text: initial is CustomerModel
          ? initial.notes
          : initial is ContractModel
          ? initial.notes
          : '',
    );
    _durationUnit = initial is ContractModel
        ? initial.durationUnit
        : ContractDurationUnit.year;
    _durationCount = TextEditingController(
      text: initial is ContractModel ? '${initial.durationCount}' : '1',
    );
    _customerId = initial is ContractModel
        ? initial.customerId
        : widget.store.customers.firstOrNull?.id;
    _adSpaceId = initial is ContractModel
        ? initial.adSpaceId
        : widget.store.adSpaces.firstOrNull?.id;
    _startDate = ContractDateHelper.dateOnly(
      initial is ContractModel ? initial.startDate : DateTime.now(),
    );
    _endDate = ContractDateHelper.dateOnly(
      initial is ContractModel
          ? widget.isRenewal
                ? ContractDateHelper.addDuration(
                    initial.endDate,
                    unit: _durationUnit,
                    count: int.tryParse(_durationCount.text) ?? 1,
                  )
                : initial.endDate
          : ContractDateHelper.addDuration(
              _startDate,
              unit: _durationUnit,
              count: int.tryParse(_durationCount.text) ?? 1,
            ),
    );
    _active = widget.isRenewal
        ? true
        : initial is ContractModel
        ? initial.isActive
        : true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _company,
      _phone,
      _email,
      _location,
      _description,
      _price,
      _notes,
      _durationCount,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _title => widget.isRenewal
      ? 'Sözleşmeyi uzat'
      : widget.initial == null
      ? 'Yeni kayıt'
      : 'Kaydı düzenle';

  void _updateStartDate(DateTime value) {
    setState(() {
      _startDate = value;
      _recalculateEndDate();
    });
  }

  void _updateEndDate(DateTime value) {
    setState(() => _endDate = value);
  }

  void _recalculateEndDate() {
    final count = int.tryParse(_durationCount.text.trim());
    if (count == null || count < 1) return;
    final extensionBase = widget.isRenewal && widget.initial is ContractModel
        ? (widget.initial as ContractModel).endDate
        : _startDate;
    _endDate = ContractDateHelper.addDuration(
      extensionBase,
      unit: _durationUnit,
      count: count,
    );
  }

  void _setDurationUnit(ContractDurationUnit unit) {
    setState(() {
      _durationUnit = unit;
      _recalculateEndDate();
    });
  }

  void _setDurationCount(String value) {
    final count = int.tryParse(value);
    if (count == null || count < 1 || count > 99) return;
    setState(_recalculateEndDate);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.store.currentUser?.role == AppRole.supervisor &&
        widget.type == RecordType.contracts &&
        _parsePrice() <= 0) {
      setState(() => _error = 'Birim fiyat sıfırdan büyük olmalıdır.');
      return;
    }
    final id = widget.isRenewal
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : switch (widget.initial) {
            AdSpaceModel value => value.id,
            CustomerModel value => value.id,
            ContractModel value => value.id,
            _ => DateTime.now().microsecondsSinceEpoch.toString(),
          };
    try {
      if (widget.type == RecordType.adSpaces) {
        await widget.store.saveAdSpace(
          AdSpaceModel(
            id: id,
            name: _name.text.trim(),
            location: _location.text.trim(),
            description: _description.text.trim(),
            monthlyPrice: _parsePrice(),
            isAvailable: widget.initial is AdSpaceModel
                ? widget.initial.isAvailable
                : true,
          ),
        );
      } else if (widget.type == RecordType.customers) {
        await widget.store.saveCustomer(
          CustomerModel(
            id: id,
            name: _name.text.trim(),
            company: _company.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            notes: _notes.text.trim(),
          ),
        );
      } else {
        final contract = ContractModel(
          id: id,
          customerId: _customerId!,
          adSpaceId: _adSpaceId!,
          startDate: _startDate,
          endDate: _endDate,
          monthlyPrice: _parsePrice(),
          durationUnit: _durationUnit,
          durationCount: int.parse(_durationCount.text),
          notes: _notes.text.trim(),
          isActive: _active,
        );
        if (widget.isRenewal && widget.initial is ContractModel) {
          await widget.store.renewContract(
            (widget.initial as ContractModel).id,
            contract,
          );
        } else {
          await widget.store.saveContract(contract);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'İşlem tamamlanamadı: $error');
    }
  }

  double _parsePrice() =>
      double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0;

  Widget _textField(
    String label,
    TextEditingController controller, {
    bool required = false,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? '$label zorunludur.'
                  : null
            : null,
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime value,
    bool isStart, {
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _DatePartsField(
      label: label,
      initialDate: value,
      readOnly: readOnly,
      onChanged: isStart ? _updateStartDate : _updateEndDate,
      validator: isStart
          ? null
          : (date) => date.isBefore(_startDate)
                ? 'Bitiş tarihi başlangıç tarihinden sonra olmalı.'
                : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isContract = widget.type == RecordType.contracts;
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.type == RecordType.adSpaces) ...[
                  _textField('Alan adı', _name, required: true),
                  _textField('Konum', _location),
                  _textField(
                    'Aylık kira (₺)',
                    _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _textField('Açıklama', _description, maxLines: 3),
                ],
                if (widget.type == RecordType.customers) ...[
                  _textField('Ad soyad', _name, required: true),
                  _textField('Firma', _company),
                  _textField(
                    'Telefon',
                    _phone,
                    keyboardType: TextInputType.phone,
                  ),
                  _textField(
                    'E-posta (bilgi amaçlı)',
                    _email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _textField('Notlar', _notes, maxLines: 3),
                ],
                if (isContract) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _customerId,
                    decoration: const InputDecoration(labelText: 'Müşteri'),
                    items: widget.store.customers
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _customerId = value),
                    validator: (value) =>
                        value == null ? 'Müşteri seçin.' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _adSpaceId,
                    decoration: const InputDecoration(
                      labelText: 'Reklam alanı',
                    ),
                    items: widget.store.adSpaces
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _adSpaceId = value),
                    validator: (value) =>
                        value == null ? 'Reklam alanı seçin.' : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sözleşme süresi',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextFormField(
                          controller: _durationCount,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Süre',
                            suffixText: 'adet',
                          ),
                          validator: (value) {
                            final count = int.tryParse(value ?? '');
                            return count == null || count < 1
                                ? 'En az 1 olmalı.'
                                : null;
                          },
                          onChanged: _setDurationCount,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<ContractDurationUnit>(
                          segments: const [
                            ButtonSegment(
                              value: ContractDurationUnit.month,
                              label: Text('Aylık'),
                            ),
                            ButtonSegment(
                              value: ContractDurationUnit.year,
                              label: Text('Yıllık'),
                            ),
                          ],
                          selected: {_durationUnit},
                          onSelectionChanged: (selection) =>
                              _setDurationUnit(selection.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _dateField(
                    'Başlangıç tarihi',
                    _startDate,
                    true,
                    readOnly: widget.isRenewal,
                  ),
                  _dateField('Bitiş tarihi', _endDate, false),
                  _textField(
                    'Aylık kira (₺)',
                    _price,
                    required: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _textField('Notlar', _notes, maxLines: 3),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sözleşme aktif'),
                    value: _active,
                    onChanged: (value) => setState(() => _active = value),
                  ),
                ],
                if (_error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}

class _DatePartsField extends StatefulWidget {
  const _DatePartsField({
    required this.label,
    required this.initialDate,
    required this.onChanged,
    this.readOnly = false,
    this.validator,
  });

  final String label;
  final DateTime initialDate;
  final ValueChanged<DateTime> onChanged;
  final bool readOnly;
  final String? Function(DateTime)? validator;

  @override
  State<_DatePartsField> createState() => _DatePartsFieldState();
}

class _DatePartsFieldState extends State<_DatePartsField> {
  late final TextEditingController _day;
  late final TextEditingController _month;
  late final TextEditingController _year;

  @override
  void initState() {
    super.initState();
    _day = TextEditingController();
    _month = TextEditingController();
    _year = TextEditingController();
    _setText(widget.initialDate);
  }

  @override
  void didUpdateWidget(covariant _DatePartsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newDate = ContractDateHelper.dateOnly(widget.initialDate);
    if (ContractDateHelper.dateOnly(oldWidget.initialDate) != newDate) {
      if (_readDate() == newDate) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            ContractDateHelper.dateOnly(widget.initialDate) != newDate) {
          return;
        }
        _setText(newDate);
      });
    }
  }

  @override
  void dispose() {
    _day.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  void _setText(DateTime date) {
    _day.text = date.day.toString().padLeft(2, '0');
    _month.text = date.month.toString().padLeft(2, '0');
    _year.text = date.year.toString().padLeft(4, '0');
  }

  DateTime? _readDate() {
    final day = int.tryParse(_day.text);
    final month = int.tryParse(_month.text);
    final year = int.tryParse(_year.text);
    if (day == null ||
        month == null ||
        year == null ||
        year < 2000 ||
        year > 2100) {
      return null;
    }
    if (month < 1 || month > 12) return null;
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day < 1 || day > lastDay) return null;
    return DateTime(year, month, day);
  }

  void _handleInput(FormFieldState<DateTime> fieldState) {
    final value = _readDate();
    fieldState.didChange(value);
    if (value != null) widget.onChanged(value);
  }

  Future<void> _pickDate(FormFieldState<DateTime> fieldState) async {
    final current = _readDate() ?? widget.initialDate;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('tr', 'TR'),
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    _setText(picked);
    fieldState.didChange(picked);
    widget.onChanged(ContractDateHelper.dateOnly(picked));
  }

  Widget _partInput({
    required String hint,
    required TextEditingController controller,
    required int maxLength,
    required FormFieldState<DateTime> fieldState,
  }) => Expanded(
    flex: hint == 'YYYY' ? 3 : 2,
    child: TextFormField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      enabled: !widget.readOnly,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ],
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (_) => _handleInput(fieldState),
    ),
  );

  @override
  Widget build(BuildContext context) => FormField<DateTime>(
    initialValue: widget.initialDate,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (_) {
      final date = _readDate();
      if (date == null) return 'GG / AA / YYYY biçiminde geçerli tarih girin.';
      return widget.validator?.call(date);
    },
    builder: (fieldState) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            _partInput(
              hint: 'GG',
              controller: _day,
              maxLength: 2,
              fieldState: fieldState,
            ),
            const SizedBox(width: 8),
            _partInput(
              hint: 'AA',
              controller: _month,
              maxLength: 2,
              fieldState: fieldState,
            ),
            const SizedBox(width: 8),
            _partInput(
              hint: 'YYYY',
              controller: _year,
              maxLength: 4,
              fieldState: fieldState,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Takvimden seç',
              onPressed: widget.readOnly ? null : () => _pickDate(fieldState),
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          ],
        ),
        if (fieldState.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              fieldState.errorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
}
