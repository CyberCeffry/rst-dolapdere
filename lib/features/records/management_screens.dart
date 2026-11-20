import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/services/app_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/contract_date_helper.dart';
import '../../core/utils/contract_remaining_time.dart';
import '../../core/utils/date_helper.dart';
import '../../core/utils/turkish_text.dart';
import '../contracts/services/contract_pdf_service.dart';
import '../contracts/services/contract_file_service.dart';
import 'services/ad_space_pdf_service.dart';
import '../../models/ad_space_model.dart';
import '../../models/contract_history_entry.dart';
import '../../models/contract_model.dart';
import '../../models/customer_model.dart';

enum RecordType { adSpaces, customers, contracts }

enum ContractListFilter { all, active, upcoming, notStarted, passive, expired }

enum EndedContractFilter { all, finalized, expired }

enum AdSpaceListFilter { all, available, occupied, expiring }

enum CustomerListFilter { all, withActive, withoutActive, noPhone }

enum CustomerSort { nameAsc, nameDesc, newest, oldest, mostActive }

enum AdSpaceSort { nameAsc, nameDesc, endAsc, priceDesc, priceAsc }

enum ContractSort {
  endAsc,
  endDesc,
  startDesc,
  startAsc,
  spaceAsc,
  spaceDesc,
  tenantAsc,
  tenantDesc,
  priceDesc,
  priceAsc,
}

enum ContractDateField { end, start }

/// Sözleşmenin kalan süresi (yazı olarak).
String contractRemainingLabel(ContractModel contract) {
  if (contract.isFinalized) return 'Bitti';
  final days = DateHelper.daysUntil(contract.endDate);
  if (days < 0) return 'Süresi doldu';
  if (days == 0) return 'Bugün bitiyor';
  return ContractRemainingTime.format(days);
}

/// Sözleşme PDF'ini açar (hata olursa mesaj gösterir).
Future<void> openContractPdfFile(
  BuildContext context,
  ContractModel contract,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await ContractFileService.open(contract.pdfPath);
  if (error != null) {
    messenger?.showSnackBar(SnackBar(content: Text(error)));
  }
}

/// Sözleşme detay penceresi (Sözleşmeler ve Bildirimler ekranlarında ortak).
Future<void> showContractDetails(
  BuildContext context,
  AppStore store,
  ContractModel contract,
) => showDialog<void>(
  context: context,
  builder: (context) => ContractDetailsDialog(store: store, contract: contract),
);

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({
    super.key,
    required this.store,
    required this.type,
    this.showEndedContracts = false,
    this.initialContractFilter = ContractListFilter.all,
    this.initialAdSpaceFilter = AdSpaceListFilter.all,
  });

  final AppStore store;
  final RecordType type;
  final bool showEndedContracts;
  final ContractListFilter initialContractFilter;
  final AdSpaceListFilter initialAdSpaceFilter;

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  late ContractListFilter _contractFilter;
  late AdSpaceListFilter _adSpaceFilter;
  CustomerListFilter _customerFilter = CustomerListFilter.all;
  CustomerSort _customerSort = CustomerSort.nameAsc;
  ContractSort _contractSort = ContractSort.endAsc;
  AdSpaceSort _adSpaceSort = AdSpaceSort.nameAsc;
  EndedContractFilter _endedFilter = EndedContractFilter.all;
  DateTimeRange? _dateRange;
  ContractDateField _dateField = ContractDateField.end;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _contractFilter = widget.initialContractFilter;
    _adSpaceFilter = widget.initialAdSpaceFilter;
    if (widget.showEndedContracts) _contractSort = ContractSort.endDesc;
  }

  String get _title => switch (widget.type) {
    RecordType.adSpaces => 'Reklam Alanları',
    RecordType.customers => 'Müşteriler',
    RecordType.contracts => 'Sözleşmeler',
  };

  List<dynamic> get _records {
    final records = switch (widget.type) {
      RecordType.adSpaces => _adSpaceRecords(),
      RecordType.customers => _customerRecords(),
      RecordType.contracts => _contractRecords(),
    };
    final query = TurkishText.fold(_query.trim());
    if (query.isEmpty) return records;
    return records
        .where(
          (record) => TurkishText.fold(_searchText(record)).contains(query),
        )
        .toList();
  }

  List<AdSpaceModel> _adSpaceRecords() {
    final store = widget.store;
    final list = store.adSpaces.where((space) {
      final contract = store.activeContractForAdSpace(space.id);
      final days = contract == null
          ? null
          : ContractRemainingTime.daysUntil(contract.endDate);
      return switch (_adSpaceFilter) {
        AdSpaceListFilter.all => true,
        AdSpaceListFilter.available => contract == null,
        AdSpaceListFilter.occupied => contract != null,
        AdSpaceListFilter.expiring => days != null && days <= 10,
      };
    }).toList();
    int endDays(AdSpaceModel space) {
      final contract = store.activeContractForAdSpace(space.id);
      return contract == null
          ? 1 << 30
          : ContractRemainingTime.daysUntil(contract.endDate);
    }

    list.sort((a, b) {
      final result = switch (_adSpaceSort) {
        AdSpaceSort.nameAsc => TurkishText.compare(a.name, b.name),
        AdSpaceSort.nameDesc => TurkishText.compare(b.name, a.name),
        AdSpaceSort.endAsc => endDays(a).compareTo(endDays(b)),
        AdSpaceSort.priceDesc => b.monthlyPrice.compareTo(a.monthlyPrice),
        AdSpaceSort.priceAsc => a.monthlyPrice.compareTo(b.monthlyPrice),
      };
      return result != 0 ? result : TurkishText.compare(a.name, b.name);
    });
    return list;
  }

  List<CustomerModel> _customerRecords() {
    final counts = <String, int>{};
    for (final contract in widget.store.activeContracts) {
      counts[contract.customerId] = (counts[contract.customerId] ?? 0) + 1;
    }
    int activeCount(CustomerModel customer) => counts[customer.id] ?? 0;
    // Yeni kayıtların kimliği oluşturulma anıdır (mikrosaniye); eskiler 0 sayılır.
    int created(CustomerModel customer) => int.tryParse(customer.id) ?? 0;
    final list = widget.store.customers.where((customer) {
      return switch (_customerFilter) {
        CustomerListFilter.all => true,
        CustomerListFilter.withActive => activeCount(customer) > 0,
        CustomerListFilter.withoutActive => activeCount(customer) == 0,
        CustomerListFilter.noPhone => customer.phone.trim().isEmpty,
      };
    }).toList();
    list.sort((a, b) {
      final result = switch (_customerSort) {
        CustomerSort.nameAsc => TurkishText.compare(a.name, b.name),
        CustomerSort.nameDesc => TurkishText.compare(b.name, a.name),
        CustomerSort.newest => created(b).compareTo(created(a)),
        CustomerSort.oldest => created(a).compareTo(created(b)),
        CustomerSort.mostActive => activeCount(b).compareTo(activeCount(a)),
      };
      return result != 0 ? result : TurkishText.compare(a.name, b.name);
    });
    return list;
  }

  bool _inDateRange(ContractModel contract) {
    final range = _dateRange;
    if (range == null) return true;
    final value = ContractDateHelper.dateOnly(
      _dateField == ContractDateField.end
          ? contract.endDate
          : contract.startDate,
    );
    final from = ContractDateHelper.dateOnly(range.start);
    final to = ContractDateHelper.dateOnly(range.end);
    return !value.isBefore(from) && !value.isAfter(to);
  }

  List<ContractModel> _contractRecords() {
    final store = widget.store;
    final base = widget.showEndedContracts
        ? store.endedContracts
        : store.contracts.where((contract) => !contract.isFinalized).toList();
    final filtered = base.where((contract) {
      final days = DateHelper.daysUntil(contract.endDate);
      final startsIn = DateHelper.daysUntil(contract.startDate);
      final statusOk = widget.showEndedContracts
          ? switch (_endedFilter) {
              EndedContractFilter.all => true,
              EndedContractFilter.finalized => contract.isFinalized,
              EndedContractFilter.expired => !contract.isFinalized && days < 0,
            }
          : switch (_contractFilter) {
              ContractListFilter.all => true,
              ContractListFilter.active =>
                store.activeContracts.any(
                      (active) => active.id == contract.id,
                    ) ||
                    (contract.isActive &&
                        !contract.isFinalized &&
                        startsIn <= 0 &&
                        days >= 0),
              ContractListFilter.upcoming => days >= 0 && days <= 10,
              ContractListFilter.notStarted => startsIn > 0,
              ContractListFilter.passive =>
                !contract.isActive && !contract.isFinalized,
              ContractListFilter.expired => days < 0,
            };
      return statusOk && _inDateRange(contract);
    }).toList();

    String spaceName(ContractModel c) =>
        store.adSpaceFor(c.adSpaceId)?.name ?? '';
    String tenantName(ContractModel c) =>
        store.customerFor(c.customerId)?.name ?? '';
    filtered.sort((a, b) {
      final result = switch (_contractSort) {
        ContractSort.endAsc => a.endDate.compareTo(b.endDate),
        ContractSort.endDesc => b.endDate.compareTo(a.endDate),
        ContractSort.startDesc => b.startDate.compareTo(a.startDate),
        ContractSort.startAsc => a.startDate.compareTo(b.startDate),
        ContractSort.spaceAsc => TurkishText.compare(
          spaceName(a),
          spaceName(b),
        ),
        ContractSort.spaceDesc => TurkishText.compare(
          spaceName(b),
          spaceName(a),
        ),
        ContractSort.tenantAsc => TurkishText.compare(
          tenantName(a),
          tenantName(b),
        ),
        ContractSort.tenantDesc => TurkishText.compare(
          tenantName(b),
          tenantName(a),
        ),
        ContractSort.priceDesc => b.monthlyPrice.compareTo(a.monthlyPrice),
        ContractSort.priceAsc => a.monthlyPrice.compareTo(b.monthlyPrice),
      };
      return result != 0 ? result : a.endDate.compareTo(b.endDate);
    });
    return filtered;
  }

  String _searchText(dynamic record) {
    if (record is AdSpaceModel) {
      final contract = widget.store.activeContractForAdSpace(record.id);
      final tenant = contract == null
          ? ''
          : widget.store.customerFor(contract.customerId)?.name ?? '';
      return '${record.name} ${record.location} ${record.description} $tenant';
    }
    if (record is CustomerModel) {
      return '${record.name} ${record.company} ${record.address} '
          '${record.phone} ${record.email}';
    }
    final contract = record as ContractModel;
    final customer = widget.store.customerFor(contract.customerId);
    final space = widget.store.adSpaceFor(contract.adSpaceId);
    return '${customer?.name ?? ''} ${customer?.company ?? ''} '
        '${space?.name ?? ''} ${space?.location ?? ''} '
        '${contract.notes} ${contract.responsibleUsername ?? ''}';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record == null ? 'Kayıt eklendi.' : 'Kayıt güncellendi.',
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

  Future<void> _openContractPdf(ContractModel contract) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ContractFileService.open(contract.pdfPath);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _showContractDetails(ContractModel contract) => showDialog<void>(
    context: context,
    builder: (context) =>
        ContractDetailsDialog(store: widget.store, contract: contract),
  );

  Future<void> _showCustomerDetails(CustomerModel customer) => showDialog<void>(
    context: context,
    builder: (context) =>
        _CustomerDetailsDialog(store: widget.store, customer: customer),
  );

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
        filterSummary: _filterSummary(),
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
    final adSpaces = records.whereType<AdSpaceModel>().toList();

    if (adSpaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dışa aktarılacak reklam alanı bulunamadı.'),
        ),
      );
      return;
    }

    try {
      await AdSpacePdfService.exportAdSpaces(widget.store, adSpaces);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF oluşturulamadı: $error')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Filtre, sıralama ve çoklu seçim
  // ---------------------------------------------------------------------------

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasActiveFilters =>
      _contractFilter != ContractListFilter.all ||
      _endedFilter != EndedContractFilter.all ||
      _customerFilter != CustomerListFilter.all ||
      _adSpaceFilter != AdSpaceListFilter.all ||
      _dateRange != null ||
      _query.trim().isNotEmpty;

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _contractFilter = ContractListFilter.all;
      _endedFilter = EndedContractFilter.all;
      _customerFilter = CustomerListFilter.all;
      _adSpaceFilter = AdSpaceListFilter.all;
      _dateRange = null;
      _dateField = ContractDateField.end;
    });
  }

  String _contractFilterLabel(ContractListFilter filter) => switch (filter) {
    ContractListFilter.all => 'Tüm sözleşmeler',
    ContractListFilter.active => 'Aktif',
    ContractListFilter.upcoming => 'Yaklaşan (10 gün)',
    ContractListFilter.notStarted => 'Başlayacak',
    ContractListFilter.passive => 'Pasif',
    ContractListFilter.expired => 'Süresi dolanlar',
  };

  String _filterSummary() {
    final format = DateFormat('dd.MM.yyyy');
    final parts = <String>[];
    if (widget.showEndedContracts) {
      if (_endedFilter != EndedContractFilter.all) {
        parts.add(
          _endedFilter == EndedContractFilter.finalized
              ? 'Bitirilenler'
              : 'Süresi dolanlar',
        );
      }
    } else if (_contractFilter != ContractListFilter.all) {
      parts.add(_contractFilterLabel(_contractFilter));
    }
    final range = _dateRange;
    if (range != null) {
      parts.add(
        '${_dateField == ContractDateField.end ? 'Bitiş' : 'Başlangıç'}: '
        '${format.format(range.start)} - ${format.format(range.end)}',
      );
    }
    final query = _query.trim();
    if (query.isNotEmpty) parts.add('Arama: $query');
    return parts.isEmpty ? 'Tüm sözleşmeler' : parts.join(' • ');
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 15),
      initialDateRange: _dateRange,
      helpText: 'Tarih aralığı seçin',
      saveText: 'Uygula',
    );
    if (picked != null && mounted) setState(() => _dateRange = picked);
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: screenWidth < 400 ? screenWidth - 72 : 230,
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final (itemValue, text) in items)
            DropdownMenuItem<T>(
              value: itemValue,
              child: Text(text, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      ),
    );
  }

  Widget _resetButton() => TextButton.icon(
    onPressed: _resetFilters,
    icon: const Icon(Icons.filter_alt_off_outlined),
    label: const Text('Filtreleri temizle'),
  );

  List<Widget> _adSpaceControls() => [
    const SizedBox(height: 12),
    Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdown<AdSpaceListFilter>(
          label: 'Durum',
          value: _adSpaceFilter,
          items: const [
            (AdSpaceListFilter.all, 'Tüm reklam alanları'),
            (AdSpaceListFilter.available, 'Boş'),
            (AdSpaceListFilter.occupied, 'Kirada'),
            (AdSpaceListFilter.expiring, 'Süresi yaklaşan (10 gün)'),
          ],
          onChanged: (value) => setState(() => _adSpaceFilter = value),
        ),
        _dropdown<AdSpaceSort>(
          label: 'Sırala',
          value: _adSpaceSort,
          items: const [
            (AdSpaceSort.nameAsc, 'A → Z'),
            (AdSpaceSort.nameDesc, 'Z → A'),
            (AdSpaceSort.endAsc, 'Bitişi yakın önce'),
            (AdSpaceSort.priceDesc, 'Kira: yüksekten düşüğe'),
            (AdSpaceSort.priceAsc, 'Kira: düşükten yükseğe'),
          ],
          onChanged: (value) => setState(() => _adSpaceSort = value),
        ),
        if (_hasActiveFilters) _resetButton(),
      ],
    ),
  ];

  List<Widget> _customerControls() => [
    const SizedBox(height: 12),
    Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdown<CustomerListFilter>(
          label: 'Filtre',
          value: _customerFilter,
          items: const [
            (CustomerListFilter.all, 'Tüm müşteriler'),
            (CustomerListFilter.withActive, 'Aktif kiralaması olanlar'),
            (CustomerListFilter.withoutActive, 'Aktif kiralaması olmayanlar'),
            (CustomerListFilter.noPhone, 'Telefonu eksik olanlar'),
          ],
          onChanged: (value) => setState(() => _customerFilter = value),
        ),
        _dropdown<CustomerSort>(
          label: 'Sırala',
          value: _customerSort,
          items: const [
            (CustomerSort.nameAsc, 'A → Z'),
            (CustomerSort.nameDesc, 'Z → A'),
            (CustomerSort.newest, 'Eklenme: yeni önce'),
            (CustomerSort.oldest, 'Eklenme: eski önce'),
            (CustomerSort.mostActive, 'En çok aktif alan'),
          ],
          onChanged: (value) => setState(() => _customerSort = value),
        ),
        if (_hasActiveFilters) _resetButton(),
      ],
    ),
  ];

  List<Widget> _contractControls(List<dynamic> records) {
    final ended = widget.showEndedContracts;
    final format = DateFormat('dd.MM.yyyy');
    final contractRecords = records.whereType<ContractModel>().toList();
    final selected = contractRecords
        .where((contract) => _selectedIds.contains(contract.id))
        .toList();
    final allSelected =
        contractRecords.isNotEmpty && selected.length == contractRecords.length;
    final range = _dateRange;
    return [
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!ended)
            _dropdown<ContractListFilter>(
              label: 'Durum',
              value: _contractFilter,
              items: [
                for (final filter in ContractListFilter.values)
                  (filter, _contractFilterLabel(filter)),
              ],
              onChanged: (value) => setState(() => _contractFilter = value),
            ),
          if (ended)
            _dropdown<EndedContractFilter>(
              label: 'Durum',
              value: _endedFilter,
              items: const [
                (EndedContractFilter.all, 'Tüm biten sözleşmeler'),
                (EndedContractFilter.finalized, 'Bitirilenler'),
                (EndedContractFilter.expired, 'Süresi dolanlar'),
              ],
              onChanged: (value) => setState(() => _endedFilter = value),
            ),
          _dropdown<ContractSort>(
            label: 'Sırala',
            value: _contractSort,
            items: const [
              (ContractSort.endAsc, 'Bitiş: yakın önce'),
              (ContractSort.endDesc, 'Bitiş: uzak önce'),
              (ContractSort.startDesc, 'Başlangıç: yeni önce'),
              (ContractSort.startAsc, 'Başlangıç: eski önce'),
              (ContractSort.spaceAsc, 'Reklam alanı A → Z'),
              (ContractSort.spaceDesc, 'Reklam alanı Z → A'),
              (ContractSort.tenantAsc, 'Kiracı A → Z'),
              (ContractSort.tenantDesc, 'Kiracı Z → A'),
              (ContractSort.priceDesc, 'Bedel: yüksekten düşüğe'),
              (ContractSort.priceAsc, 'Bedel: düşükten yükseğe'),
            ],
            onChanged: (value) => setState(() => _contractSort = value),
          ),
          // _dropdown<ContractDateField>(
          //   label: 'Tarih alanı',
          //   value: _dateField,
          //   items: const [
          //     (ContractDateField.end, 'Bitiş tarihi'),
          //     (ContractDateField.start, 'Başlangıç tarihi'),
          //   ],
          //   onChanged: (value) => setState(() => _dateField = value),
          // ),
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_outlined),
            label: Text(
              range == null
                  ? 'İki tarih arası'
                  : '${format.format(range.start)} - ${format.format(range.end)}',
            ),
          ),
          if (range != null)
            IconButton(
              tooltip: 'Tarih filtresini temizle',
              onPressed: () => setState(() => _dateRange = null),
              icon: const Icon(Icons.close),
            ),
          if (_hasActiveFilters) _resetButton(),
          OutlinedButton.icon(
            onPressed: _toggleSelectionMode,
            icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
            label: Text(_selectionMode ? 'Seçimi kapat' : 'Çoklu seçim'),
          ),
        ],
      ),
      if (_selectionMode) ...[
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${selected.length} seçili'),
                TextButton.icon(
                  onPressed: contractRecords.isEmpty
                      ? null
                      : () => _selectAll(contractRecords),
                  icon: const Icon(Icons.select_all),
                  label: Text(allSelected ? 'Seçimi kaldır' : 'Tümünü seç'),
                ),
                FilledButton.icon(
                  onPressed: selected.isEmpty ? null : () => _bulkEnd(selected),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Bitir'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  onPressed: selected.isEmpty
                      ? null
                      : () => _bulkDelete(selected),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Sil'),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(ContractModel contract) {
    setState(() {
      if (!_selectedIds.add(contract.id)) _selectedIds.remove(contract.id);
    });
  }

  void _selectAll(List<ContractModel> visible) {
    final ids = visible.map((contract) => contract.id).toSet();
    setState(() {
      if (_selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _bulkDelete(List<ContractModel> selected) async {
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seçilenleri sil'),
        content: Text(
          '${selected.length} sözleşme kalıcı olarak silinecek. '
          'Devam etmek istiyor musunuz?',
        ),
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
    var done = 0;
    String? error;
    for (final contract in selected) {
      try {
        await widget.store.deleteContract(contract.id);
        done++;
      } catch (e) {
        error = e.toString();
      }
    }
    if (!mounted) return;
    setState(() => _selectedIds.removeAll(selected.map((c) => c.id)));
    _toast(
      error == null
          ? '$done sözleşme silindi.'
          : '$done sözleşme silindi, bazıları silinemedi: $error',
    );
  }

  Future<void> _bulkEnd(List<ContractModel> selected) async {
    final endable = selected
        .where((contract) => !contract.isFinalized)
        .toList();
    if (endable.isEmpty) {
      _toast('Seçilen sözleşmelerin hepsi zaten bitirilmiş.');
      return;
    }
    final skipped = selected.length - endable.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seçilenleri bitir'),
        content: Text(
          '${endable.length} sözleşme kalıcı olarak bitenler listesine alınır. '
          'Daha sonra yeniden açılamaz.'
          '${skipped > 0 ? '\n$skipped sözleşme zaten bitmiş, atlanacak.' : ''}',
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
    var done = 0;
    String? error;
    for (final contract in endable) {
      try {
        await widget.store.markContractEnded(contract.id);
        done++;
      } catch (e) {
        error = e.toString();
      }
    }
    if (!mounted) return;
    setState(() => _selectedIds.removeAll(selected.map((c) => c.id)));
    _toast(
      error == null
          ? '$done sözleşme bitirildi.'
          : '$done sözleşme bitirildi, bazıları bitirilemedi: $error',
    );
  }

  Widget _summaryLine(List<dynamic> records) {
    final contracts = records.whereType<ContractModel>().toList();
    final text = widget.type == RecordType.contracts
        ? '${contracts.length} sözleşme • Toplam bedel: '
              '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(contracts.fold<double>(0, (sum, item) => sum + item.monthlyPrice))}'
        : '${records.length} kayıt';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
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

  /// Aktif sözleşme için kalan süre: 30 gün ve altı gün, üstü ay olarak yazılır.
  /// (10 gün ve altındaki gösterim ayrı dalda, olduğu gibi kalır.)
  String _activeStatus(DateTime endDate, int days) {
    if (days <= 30) return 'Aktif • $days gün kaldı';
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    var months = (end.year - today.year) * 12 + end.month - today.month;
    if (end.day < today.day) months--;
    if (months < 1) return 'Aktif • $days gün kaldı';
    // Bugünden "months" ay sonrası (ay sonuna taşarsa ayın son günü).
    final anchorMonth = today.month + months;
    final lastDay = DateTime.utc(today.year, anchorMonth + 1, 0).day;
    final anchor = DateTime.utc(
      today.year,
      anchorMonth,
      today.day > lastDay ? lastDay : today.day,
    );
    final extraDays = end.difference(anchor).inDays;
    return extraDays > 0
        ? 'Aktif • $months ay $extraDays gün kaldı'
        : 'Aktif • $months ay kaldı';
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
    Color statusColor = Theme.of(context).colorScheme.onSurfaceVariant;
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
        record.address,
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
      title = space?.name ?? 'Reklam alanı';
      subtitle =
          '${customer?.name ?? 'Kiracı'} • '
          '${DateFormat('dd.MM.yyyy').format(contract.startDate)} - '
          '${DateFormat('dd.MM.yyyy').format(contract.endDate)} • '
          '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(contract.monthlyPrice)}'
          '${contract.responsibleUsername == null ? '' : ' • Sorumlu: ${contract.responsibleUsername}'}';
      icon = Icons.description_outlined;
      status = contract.isFinalized
          ? 'Bitti olarak işaretlendi'
          : days < 0
          ? 'Süresi doldu'
          : !contract.isActive
          ? 'Pasif'
          : days <= 10
          ? '$days gün kaldı'
          : _activeStatus(contract.endDate, days);
      statusColor = contract.isFinalized || !contract.isActive || days < 0
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : days <= 10
          ? AppColors.danger
          : AppColors.success;
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        onTap: _selectionMode && record is ContractModel
            ? () => _toggleSelected(record)
            : null,
        leading: _selectionMode && record is ContractModel
            ? Checkbox(
                value: _selectedIds.contains(record.id),
                onChanged: (_) => _toggleSelected(record),
              )
            : CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
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
          width: 250,
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
                      case 'pdf':
                        _openContractPdf(record);
                      case 'toggle':
                        _toggleContractActive(record);
                      case 'edit':
                        _edit(record);
                      case 'end':
                        _markContractEnded(record);
                      case 'renew':
                        _renewContract(record);
                      case 'delete':
                        _delete(record);
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
                  if (record is ContractModel) {
                    final ended =
                        record.isFinalized ||
                        DateHelper.daysUntil(record.endDate) < 0;
                    return [
                      const PopupMenuItem(
                        value: 'details',
                        child: Text('Detayları görüntüle'),
                      ),
                      if (record.hasPdf)
                        const PopupMenuItem(
                          value: 'pdf',
                          child: Text('Sözleşme PDF\'ini görüntüle'),
                        ),
                      if (!ended)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Düzenle'),
                        ),
                      if (!record.isFinalized)
                        const PopupMenuItem(
                          value: 'end',
                          child: Text('Bitti olarak işaretle'),
                        ),
                      const PopupMenuItem(
                        value: 'renew',
                        child: Text('Sözleşmeyi uzat'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('Sil')),
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
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (!widget.showEndedContracts)
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
              if (contracts) ..._contractControls(records),
              if (widget.type == RecordType.adSpaces) ..._adSpaceControls(),
              if (widget.type == RecordType.customers) ..._customerControls(),
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
              if (records.isNotEmpty) _summaryLine(records),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'Henüz kayıt bulunmuyor.'
                                : 'Aramanızla eşleşen kayıt yok.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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

class ContractDetailsDialog extends StatelessWidget {
  const ContractDetailsDialog({required this.store, required this.contract});

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
              Text('Kalan süre: ${contractRemainingLabel(contract)}'),
              Text(
                'Toplam tutar: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(contract.monthlyPrice)}',
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
        if (contract.hasPdf)
          TextButton.icon(
            onPressed: () => openContractPdfFile(context, contract),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Sözleşme PDF'),
          ),
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
              if (customer.address.isNotEmpty)
                Text('Adres: ${customer.address}'),
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
                final days = DateHelper.daysUntil(contract.endDate);
                final remaining = ended
                    ? 'Bitti'
                    : startsLater
                    ? 'Başlayacak'
                    : ContractRemainingTime.format(days);
                final urgent =
                    !ended &&
                    !startsLater &&
                    ContractRemainingTime.isUrgent(days);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  isThreeLine: true,
                  leading: const Icon(Icons.location_city_outlined),
                  title: Text(space?.name ?? 'Silinmiş reklam alanı'),
                  subtitle: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${space?.location.isNotEmpty == true ? '${space!.location} • ' : ''}'
                              '${dateFormat.format(contract.startDate)} - ${dateFormat.format(contract.endDate)}\n',
                        ),
                        const TextSpan(text: 'Kalan süre: '),
                        TextSpan(
                          text: remaining,
                          style: urgent
                              ? const TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ended
                            ? 'Bitti'
                            : startsLater
                            ? 'Başlayacak'
                            : 'Aktif',
                      ),
                      if (contract.hasPdf)
                        IconButton(
                          tooltip: 'Sözleşme PDF\'ini görüntüle',
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          onPressed: () =>
                              openContractPdfFile(context, contract),
                        ),
                    ],
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
  late final TextEditingController _address;
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
  String? _existingPdf;
  String? _newPdfSource;
  bool _removePdf = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _existingPdf = initial is ContractModel ? initial.pdfPath : null;
    _name = TextEditingController(
      text: initial is AdSpaceModel
          ? initial.name
          : initial is CustomerModel
          ? initial.name
          : '',
    );
    _company = TextEditingController(
      text: initial is CustomerModel
          ? (initial.company.trim().isNotEmpty ? initial.company : initial.name)
          : '',
    );
    _address = TextEditingController(
      text: initial is CustomerModel ? initial.address : '',
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
      _address,
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
            name: _company.text.trim(),
            company: _company.text.trim(),
            address: _address.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            notes: _notes.text.trim(),
          ),
        );
      } else {
        final customer = widget.store.customerFor(_customerId!);
        final space = widget.store.adSpaceFor(_adSpaceId!);
        final companyTitle = customer?.company.trim() ?? '';
        final pdfPlan = await ContractFileService.prepare(
          spaceName: space?.name ?? '',
          tenantTitle: companyTitle.isNotEmpty
              ? companyTitle
              : (customer?.name ?? ''),
          startDate: _startDate,
          endDate: _endDate,
          existingRelativePath: _existingPdf,
          pickedSourcePath: _newPdfSource,
          remove: _removePdf,
        );
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
          pdfPath: pdfPlan.relativePath,
        );
        try {
          if (widget.isRenewal && widget.initial is ContractModel) {
            await widget.store.renewContract(
              (widget.initial as ContractModel).id,
              contract,
            );
          } else {
            await widget.store.saveContract(contract);
          }
        } catch (_) {
          await pdfPlan.rollback();
          rethrow;
        }
        await pdfPlan.commit();
        final pdfWarning = pdfPlan.commitWarning;
        if (pdfWarning != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(pdfWarning)));
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'İşlem tamamlanamadı: $error');
    }
  }

  Future<void> _pickPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ContractFileService.pickPdf();
      if (path == null || !mounted) return;
      setState(() {
        _newPdfSource = path;
        _removePdf = false;
        _error = null;
      });
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('PDF seçilemedi: $error')));
    }
  }

  String _fileLabel(String path) => path.split(RegExp(r'[\\/]')).last;

  Widget _pdfSection() {
    final picked = _newPdfSource;
    final existing = _removePdf ? null : _existingPdf;
    final hasExisting = (existing ?? '').trim().isNotEmpty;
    final hasAny = picked != null || hasExisting;
    final String statusText;
    if (picked != null) {
      statusText = 'Seçilen PDF: ${_fileLabel(picked)}';
    } else if (hasExisting) {
      statusText = 'Kayıtlı PDF: ${_fileLabel(existing!)}';
    } else if (_removePdf) {
      statusText = 'Kaydedince PDF kaldırılacak.';
    } else {
      statusText = 'Henüz PDF eklenmedi.';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _pickPdf,
            icon: const Icon(Icons.upload_file),
            label: Text(hasAny ? 'PDF\'i değiştir' : 'PDF yükle'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasAny)
            IconButton(
              tooltip: 'PDF\'i kaldır',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                if (picked != null) {
                  _newPdfSource = null;
                } else {
                  _removePdf = true;
                }
              }),
            ),
        ],
      ),
    );
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
                  _textField('Firma adı', _company, required: true),
                  _textField('Adres', _address, maxLines: 2),
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
                    'Toplam tutar (₺)',
                    _price,
                    required: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _textField('Notlar', _notes, maxLines: 3),
                  if (ContractFileService.isSupported) _pdfSection(),
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
