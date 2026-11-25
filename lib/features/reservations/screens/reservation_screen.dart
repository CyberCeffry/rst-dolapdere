import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../models/reservation_model.dart';
import '../../../shared/widgets/searchable_picker.dart';
import '../../../shared/widgets/space_form.dart';
import '../../../shared/widgets/space_hover.dart';
import '../../../shared/widgets/space_menu.dart';
import '../../records/management_screens.dart';
import '../services/reservation_pdf_service.dart';

enum _ReservationFilter { all, occupied, empty }

enum _ReservationSort {
  spaceAsc,
  spaceDesc,
  reserverAsc,
  tenantEndAsc,
  newest,
  oldest,
}

/// Rezervasyonlar: bir reklam alanı için mevcut kiracıdan sonraki kullanıcı.
class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _ReservationFilter _filter = _ReservationFilter.all;
  _ReservationSort _sort = _ReservationSort.spaceAsc;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<ReservationModel> _records() {
    final store = widget.store;
    String spaceName(ReservationModel r) =>
        store.adSpaceFor(r.adSpaceId)?.name ?? '';
    String reserverName(ReservationModel r) =>
        store.customerFor(r.customerId)?.name ?? '';
    int tenantEnd(ReservationModel r) {
      final contract = store.activeContractForAdSpace(r.adSpaceId);
      return contract == null
          ? 1 << 30
          : ContractRemainingTime.daysUntil(contract.endDate);
    }

    final list = store.reservations.where((r) {
      final occupied = store.activeContractForAdSpace(r.adSpaceId) != null;
      return switch (_filter) {
        _ReservationFilter.all => true,
        _ReservationFilter.occupied => occupied,
        _ReservationFilter.empty => !occupied,
      };
    }).toList();

    final query = TurkishText.fold(_query.trim());
    final searched = query.isEmpty
        ? list
        : list.where((r) {
            final contract = store.activeContractForAdSpace(r.adSpaceId);
            final tenant = contract == null
                ? ''
                : store.customerFor(contract.customerId)?.name ?? '';
            return TurkishText.fold(
              '${spaceName(r)} ${reserverName(r)} $tenant ${r.notes}',
            ).contains(query);
          }).toList();

    searched.sort((a, b) {
      final result = switch (_sort) {
        _ReservationSort.spaceAsc => TurkishText.compare(
          spaceName(a),
          spaceName(b),
        ),
        _ReservationSort.spaceDesc => TurkishText.compare(
          spaceName(b),
          spaceName(a),
        ),
        _ReservationSort.reserverAsc => TurkishText.compare(
          reserverName(a),
          reserverName(b),
        ),
        _ReservationSort.tenantEndAsc => tenantEnd(a).compareTo(tenantEnd(b)),
        _ReservationSort.newest => b.createdAt.compareTo(a.createdAt),
        _ReservationSort.oldest => a.createdAt.compareTo(b.createdAt),
      };
      return result != 0
          ? result
          : TurkishText.compare(spaceName(a), spaceName(b));
    });
    return searched;
  }

  String _filterSummary() {
    final parts = <String>[];
    switch (_filter) {
      case _ReservationFilter.all:
        break;
      case _ReservationFilter.occupied:
        parts.add('Alan kirada');
      case _ReservationFilter.empty:
        parts.add('Alan boş');
    }
    final query = _query.trim();
    if (query.isNotEmpty) parts.add('Arama: $query');
    return parts.isEmpty ? 'Tüm rezervasyonlar' : parts.join(' • ');
  }

  Future<void> _export(List<ReservationModel> records) async {
    try {
      await ReservationPdfService.exportReservations(
        widget.store,
        records,
        filterSummary: _filterSummary(),
      );
    } catch (error) {
      _toast('PDF oluşturulamadı: $error');
    }
  }

  Future<void> _openForm([ReservationModel? initial]) async {
    if (widget.store.customers.isEmpty || widget.store.adSpaces.isEmpty) {
      _toast('Önce müşteri ve reklam alanı ekleyin.');
      return;
    }
    await showDialog<bool>(
      context: context,
      builder: (context) =>
          _ReservationFormDialog(store: widget.store, initial: initial),
    );
  }

  Future<void> _delete(ReservationModel reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rezervasyonu sil'),
        content: const Text('Bu rezervasyon silinecek. Devam edilsin mi?'),
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
    await widget.store.deleteReservation(reservation.id);
    _toast('Rezervasyon silindi.');
  }

  List<ReservationModel> _selected(List<ReservationModel> records) =>
      records.where((item) => _selectedIds.contains(item.id)).toList();

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(ReservationModel reservation) {
    setState(() {
      if (!_selectedIds.add(reservation.id)) {
        _selectedIds.remove(reservation.id);
      }
    });
  }

  void _selectAll(List<ReservationModel> visible) {
    final ids = visible.map((item) => item.id).toSet();
    setState(() {
      if (_selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _bulkDelete(List<ReservationModel> selected) async {
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seçilenleri sil'),
        content: Text('${selected.length} rezervasyon silinecek. Devam edilsin mi?'),
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
    for (final reservation in selected) {
      await widget.store.deleteReservation(reservation.id);
    }
    if (!mounted) return;
    setState(() => _selectedIds.removeAll(selected.map((item) => item.id)));
    _toast('${selected.length} rezervasyon silindi.');
  }

  /// Rezervasyondan sözleşme başlatır.
  /// true: başlatıldı, false: alan kirada olduğu için atlandı, null: vazgeçildi.
  Future<bool?> _startContract(
    ReservationModel reservation, {
    bool quiet = false,
  }) async {
    final store = widget.store;
    final space = store.adSpaceFor(reservation.adSpaceId);
    final current = store.activeContractForAdSpace(reservation.adSpaceId);
    if (current != null) {
      if (!quiet) {
        final tenant = store.customerFor(current.customerId)?.name ?? 'Kiracı';
        _toast(
          '${space?.name ?? 'Alan'} şu an kirada ($tenant, '
          '${ContractRemainingTime.formatDetailed(current.endDate)} kaldı). '
          'Alan boşalınca sözleşme başlatabilirsiniz.',
        );
      }
      return false;
    }
    final before = store.contracts.length;
    final saved = await showStartContractDialog(
      context,
      store,
      customerId: reservation.customerId,
      adSpaceId: reservation.adSpaceId,
    );
    if (saved != true) return null;
    if (store.contracts.length > before) {
      await store.deleteReservation(reservation.id);
      if (!quiet) _toast('Sözleşme başlatıldı, rezervasyon kaldırıldı.');
    }
    return true;
  }

  Future<void> _bulkStart(List<ReservationModel> selected) async {
    if (selected.isEmpty) return;
    var started = 0;
    var skipped = 0;
    for (final reservation in selected) {
      if (!mounted) return;
      final result = await _startContract(reservation, quiet: true);
      if (result == null) break; // Vazgeçildi: kalanları işleme
      if (result) {
        started++;
        _selectedIds.remove(reservation.id);
      } else {
        skipped++;
      }
    }
    if (!mounted) return;
    setState(() {});
    _toast(
      '$started sözleşme başlatıldı'
      '${skipped > 0 ? ', $skipped alan kirada olduğu için atlandı' : ''}.',
    );
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

  Widget _tile(ReservationModel reservation) {
    final store = widget.store;
    final space = store.adSpaceFor(reservation.adSpaceId);
    final reserver = store.customerFor(reservation.customerId);
    final contract = store.activeContractForAdSpace(reservation.adSpaceId);
    final tenant = contract == null
        ? null
        : store.customerFor(contract.customerId);
    final days = contract == null
        ? null
        : ContractRemainingTime.daysUntil(contract.endDate);
    final urgent = days != null && ContractRemainingTime.isUrgent(days);
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final dateFormat = DateFormat('dd.MM.yyyy');

    final narrow = MediaQuery.sizeOf(context).width < 760;
    final canStart = contract == null;
    final startColor = canStart
        ? AppColors.success
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: SpaceHover(
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        isThreeLine: true,
        onTap: _selectionMode ? () => _toggleSelected(reservation) : null,
        leading: _selectionMode
            ? Checkbox(
                value: _selectedIds.contains(reservation.id),
                onChanged: (_) => _toggleSelected(reservation),
              )
            : CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                child: const Icon(
                  Icons.bookmark_border,
                  color: AppColors.primary,
                ),
              ),
        title: Text(
          space?.name ?? 'Silinmiş reklam alanı',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Rezerve eden: ${reserver?.name ?? 'Bilinmiyor'}\n',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (contract == null)
                  const TextSpan(text: 'Mevcut kiracı: yok (alan boş)\n')
                else ...[
                  TextSpan(
                    text: 'Mevcut kiracı: ${tenant?.name ?? 'Bilinmiyor'}\n',
                  ),
                  const TextSpan(text: 'Kalan süre: '),
                  TextSpan(
                    text:
                        '${ContractRemainingTime.formatDetailed(contract.endDate)}\n',
                    style: urgent
                        ? const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                  TextSpan(
                    text:
                        'Verilen tutar: ${currency.format(contract.monthlyPrice)}\n',
                  ),
                ],
                TextSpan(
                  text:
                      'Rezervasyon: ${dateFormat.format(reservation.createdAt)}',
                ),
                if (reservation.notes.trim().isNotEmpty)
                  TextSpan(text: '\nNot: ${reservation.notes.trim()}'),
              ],
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (narrow)
              IconButton(
                tooltip: 'Sözleşme başlat',
                onPressed: () => _startContract(reservation),
                icon: Icon(Icons.play_circle_outline, color: startColor),
              )
            else
              TextButton.icon(
                onPressed: () => _startContract(reservation),
                icon: Icon(Icons.play_circle_outline, color: startColor),
                label: Text(
                  'Sözleşme başlat',
                  style: TextStyle(color: startColor),
                ),
              ),
            SpaceMenuButton<String>(
              tooltip: 'Kayıt işlemleri',
              onSelected: (value) {
                if (value == 'edit') _openForm(reservation);
                if (value == 'delete') _delete(reservation);
              },
              items: const [
                SpaceMenuItem(
                  value: 'edit',
                  label: 'Düzenle',
                  icon: Icons.edit_outlined,
                ),
                SpaceMenuItem(
                  value: 'delete',
                  label: 'Sil',
                  icon: Icons.delete_outline,
                  destructive: true,
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width < 600
        ? 16.0
        : 24.0;
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final records = _records();
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sabit ust kisim (baslik, filtreler, arama, kayit sayisi)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text(
                    'Rezervasyonlar',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: records.isEmpty
                            ? null
                            : () => _export(records),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.add),
                        label: const Text('Yeni Rezervasyon'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Bir reklam alanı için mevcut kiracıdan sonraki kullanıcı',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _dropdown<_ReservationFilter>(
                    label: 'Durum',
                    value: _filter,
                    items: const [
                      (_ReservationFilter.all, 'Tüm rezervasyonlar'),
                      (_ReservationFilter.occupied, 'Alan şu an kirada'),
                      (_ReservationFilter.empty, 'Alan şu an boş'),
                    ],
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                  _dropdown<_ReservationSort>(
                    label: 'Sırala',
                    value: _sort,
                    items: const [
                      (_ReservationSort.spaceAsc, 'Reklam alanı A → Z'),
                      (_ReservationSort.spaceDesc, 'Reklam alanı Z → A'),
                      (_ReservationSort.reserverAsc, 'Rezerve eden A → Z'),
                      (
                        _ReservationSort.tenantEndAsc,
                        'Mevcut kiracı bitişi yakın önce',
                      ),
                      (_ReservationSort.newest, 'Rezervasyon: yeni önce'),
                      (_ReservationSort.oldest, 'Rezervasyon: eski önce'),
                    ],
                    onChanged: (value) => setState(() => _sort = value),
                  ),
                  OutlinedButton.icon(
                    onPressed: _toggleSelectionMode,
                    icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
                    label: Text(
                      _selectionMode ? 'Seçimi kapat' : 'Çoklu seçim',
                    ),
                  ),
                  if (_filter != _ReservationFilter.all ||
                      _query.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _filter = _ReservationFilter.all;
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Filtreleri temizle'),
                    ),
                ],
              ),
              if (_selectionMode) ...[
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${_selected(records).length} seçili'),
                        TextButton.icon(
                          onPressed: records.isEmpty
                              ? null
                              : () => _selectAll(records),
                          icon: const Icon(Icons.select_all),
                          label: Text(
                            records.isNotEmpty &&
                                    _selected(records).length == records.length
                                ? 'Seçimi kaldır'
                                : 'Tümünü seç',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _selected(records).isEmpty
                              ? null
                              : () => _bulkStart(_selected(records)),
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Sözleşme başlat'),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                          ),
                          onPressed: _selected(records).isEmpty
                              ? null
                              : () => _bulkDelete(_selected(records)),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Sil'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Ara',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              if (records.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${records.length} rezervasyon',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              ),
              // Yalnizca liste kismi kayar
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              if (records.isEmpty)
                Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.bookmark_border,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.store.reservations.isEmpty
                                ? 'Henüz rezervasyon yok.'
                                : 'Filtreye uyan rezervasyon bulunamadı.',
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
                ...records.map(_tile),
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

class _ReservationFormDialog extends StatefulWidget {
  const _ReservationFormDialog({required this.store, this.initial});

  final AppStore store;
  final ReservationModel? initial;

  @override
  State<_ReservationFormDialog> createState() => _ReservationFormDialogState();
}

class _ReservationFormDialogState extends State<_ReservationFormDialog> {
  late String? _adSpaceId;
  late String? _customerId;
  late final TextEditingController _notes;
  String? _error;

  List<PickerItem<String>> get _spaceItems {
    final store = widget.store;
    final items = <PickerItem<String>>[];
    for (final space in store.adSpaces) {
      final reserved = store.reservationForAdSpace(space.id);
      // Başka bir rezervasyonu olan alanlar listelenmez (alan başına tek rezervasyon).
      if (reserved != null && reserved.id != widget.initial?.id) continue;
      final contract = store.activeContractForAdSpace(space.id);
      final tenant = contract == null
          ? null
          : store.customerFor(contract.customerId)?.name;
      items.add(
        PickerItem<String>(
          value: space.id,
          label: space.name,
          subtitle: contract == null
              ? 'Boş'
              : 'Kirada • ${tenant ?? 'Bilinmiyor'} • '
                    '${ContractRemainingTime.formatDetailed(contract.endDate)} kaldı',
          searchText: '${space.location} ${space.description} ${tenant ?? ''}',
        ),
      );
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final spaces = _spaceItems;
    _adSpaceId =
        initial?.adSpaceId ?? (spaces.isEmpty ? null : spaces.first.value);
    _customerId =
        initial?.customerId ??
        (widget.store.customers.isEmpty ? null : widget.store.customers.first.id);
    _notes = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final spaceId = _adSpaceId;
    final customerId = _customerId;
    if (spaceId == null || customerId == null) {
      setState(() => _error = 'Reklam alanı ve müşteri seçin.');
      return;
    }
    try {
      await widget.store.saveReservation(
        ReservationModel(
          id:
              widget.initial?.id ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          adSpaceId: spaceId,
          customerId: customerId,
          createdAt: widget.initial?.createdAt ?? DateTime.now(),
          notes: _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'İşlem tamamlanamadı: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final spaces = _spaceItems;
    final editing = widget.initial != null;
    final nothingToReserve = spaces.isEmpty;
    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      title: SpaceDialogHeader(
        icon: Icons.bookmark_border,
        title: editing ? 'Rezervasyonu düzenle' : 'Yeni rezervasyon',
        subtitle: 'Mevcut kiracıdan sonraki kullanıcı için alan ayırın',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: nothingToReserve
              ? const Text('Tüm reklam alanları için zaten rezervasyon var.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SpaceSectionTitle(
                      text: 'Alan ve kişi',
                      icon: Icons.handshake_outlined,
                    ),
                    SearchablePicker<String>(
                      label: 'Reklam alanı',
                      value: _adSpaceId,
                      items: spaces,
                      createLabel: '+ Yeni alan ekle',
                      onCreate: () =>
                          showCreateAdSpaceDialog(context, widget.store),
                      onChanged: (value) => setState(() => _adSpaceId = value),
                    ),
                    const SizedBox(height: 14),
                    SearchablePicker<String>(
                      label: 'Rezerve eden müşteri',
                      value: _customerId,
                      items: [
                        for (final customer in widget.store.customers)
                          PickerItem<String>(
                            value: customer.id,
                            label: customer.name,
                            subtitle: customer.phone.isEmpty
                                ? null
                                : customer.phone,
                            searchText:
                                '${customer.company} ${customer.address} ${customer.email}',
                          ),
                      ],
                      createLabel: '+ Yeni müşteri ekle',
                      onCreate: () =>
                          showCreateCustomerDialog(context, widget.store),
                      onChanged: (value) =>
                          setState(() => _customerId = value),
                    ),
                    const SizedBox(height: 14),
                    const SpaceSectionTitle(
                      text: 'Not',
                      icon: Icons.notes_outlined,
                    ),
                    TextField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Not'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Kapat'),
        ),
        if (!nothingToReserve)
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Kaydet'),
          ),
      ],
    );
  }
}