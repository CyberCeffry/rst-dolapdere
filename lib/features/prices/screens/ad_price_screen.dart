import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../models/ad_price_model.dart';
import '../../../models/ad_space_model.dart';
import '../../../shared/widgets/space_form.dart';
import '../../../shared/widgets/space_hover.dart';
import '../services/ad_price_pdf_service.dart';

enum _PriceFilter { all, filled, missing }

enum _PriceSort { nameAsc, nameDesc, monthlyDesc, monthlyAsc }

/// Reklam alanları için aylık / 3 aylık / 6 aylık / 12 aylık fiyat listesi.
/// Kiracı bilgisi içermez; sözleşmelerden ve reklam alanı kayıtlarından
/// bağımsızdır ve yalnızca bu ekrandan değişir. Fiyat girişi isteğe bağlıdır;
/// kullanıcı fiyat penceresini istediği zaman kapatabilir.
class AdPriceScreen extends StatefulWidget {
  const AdPriceScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<AdPriceScreen> createState() => _AdPriceScreenState();
}

class _AdPriceScreenState extends State<AdPriceScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _PriceFilter _filter = _PriceFilter.all;
  _PriceSort _sort = _PriceSort.nameAsc;

  final NumberFormat _currency = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
  );

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

  Future<void> _edit(AdSpaceModel space) => showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        _PriceFormDialog(store: widget.store, spaces: [space]),
  );

  List<AdSpaceModel> _records() {
    final store = widget.store;
    double monthly(AdSpaceModel s) => store.adPriceFor(s.id)?.monthly ?? 0;
    bool filled(AdSpaceModel s) => store.adPriceFor(s.id)?.isComplete ?? false;

    var list = store.adSpaces.where((space) {
      return switch (_filter) {
        _PriceFilter.all => true,
        _PriceFilter.filled => filled(space),
        _PriceFilter.missing => !filled(space),
      };
    }).toList();

    final query = TurkishText.fold(_query.trim());
    if (query.isNotEmpty) {
      list = list
          .where(
            (space) => TurkishText.fold(
              '${space.name} ${space.location}',
            ).contains(query),
          )
          .toList();
    }

    list.sort((a, b) {
      final result = switch (_sort) {
        _PriceSort.nameAsc => TurkishText.compare(a.name, b.name),
        _PriceSort.nameDesc => TurkishText.compare(b.name, a.name),
        _PriceSort.monthlyDesc => monthly(b).compareTo(monthly(a)),
        _PriceSort.monthlyAsc => monthly(a).compareTo(monthly(b)),
      };
      return result != 0 ? result : TurkishText.compare(a.name, b.name);
    });
    return list;
  }

  String _filterSummary() {
    final parts = <String>[];
    switch (_filter) {
      case _PriceFilter.all:
        break;
      case _PriceFilter.filled:
        parts.add('Fiyatı girilmiş');
      case _PriceFilter.missing:
        parts.add('Fiyatı eksik');
    }
    final query = _query.trim();
    if (query.isNotEmpty) parts.add('Arama: $query');
    return parts.isEmpty ? 'Tüm reklam alanları' : parts.join(' • ');
  }

  Future<void> _export(List<AdSpaceModel> records) async {
    try {
      await AdPricePdfService.exportPrices(
        widget.store,
        records,
        filterSummary: _filterSummary(),
      );
    } catch (error) {
      _toast('PDF oluşturulamadı: $error');
    }
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

  Widget _priceChip(String label, double value) {
    final colors = Theme.of(context).colorScheme;
    final has = value > 0;
    final accent = has ? const Color(0xFF22D3EE) : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11.5),
          ),
          const SizedBox(height: 3),
          Text(
            has ? _currency.format(value) : 'Girilmedi',
            style: TextStyle(
              color: has ? colors.onSurface : AppColors.warning,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AdSpaceModel space) {
    final price = widget.store.adPriceFor(space.id);
    final complete = price?.isComplete ?? false;
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: SpaceHover(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.surfaceContainerHighest,
                    child: const Icon(
                      Icons.location_city_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          space.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (space.location.trim().isNotEmpty)
                          Text(
                            space.location.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _edit(space),
                    icon: Icon(
                      complete ? Icons.edit_outlined : Icons.add,
                      size: 18,
                    ),
                    label: Text(complete ? 'Fiyatı düzenle' : 'Fiyat gir'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _priceChip('Aylık', price?.monthly ?? 0),
                  _priceChip('3 Aylık', price?.threeMonth ?? 0),
                  _priceChip('6 Aylık', price?.sixMonth ?? 0),
                  _priceChip('12 Aylık', price?.twelveMonth ?? 0),
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
        final missingCount = widget.store.adSpacesMissingPrice.length;
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
              // Sabit üst kısım
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
                            'Reklam Alanı Fiyatları',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: records.isEmpty
                                ? null
                                : () => _export(records),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reklam alanları için isteğe bağlı aylık, 3 aylık, 6 aylık ve yıllık fiyat listesi '
                        '(sözleşmelerden bağımsızdır)',
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
                          _dropdown<_PriceFilter>(
                            label: 'Durum',
                            value: _filter,
                            items: const [
                              (_PriceFilter.all, 'Tüm reklam alanları'),
                              (_PriceFilter.filled, 'Fiyatı girilmiş'),
                              (_PriceFilter.missing, 'Fiyatı eksik'),
                            ],
                            onChanged: (value) =>
                                setState(() => _filter = value),
                          ),
                          _dropdown<_PriceSort>(
                            label: 'Sırala',
                            value: _sort,
                            items: const [
                              (_PriceSort.nameAsc, 'A → Z'),
                              (_PriceSort.nameDesc, 'Z → A'),
                              (
                                _PriceSort.monthlyDesc,
                                'Aylık: yüksekten düşüğe',
                              ),
                              (
                                _PriceSort.monthlyAsc,
                                'Aylık: düşükten yükseğe',
                              ),
                            ],
                            onChanged: (value) => setState(() => _sort = value),
                          ),
                          if (_filter != _PriceFilter.all ||
                              _query.trim().isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _query = '';
                                  _filter = _PriceFilter.all;
                                });
                              },
                              icon: const Icon(Icons.filter_alt_off_outlined),
                              label: const Text('Filtreleri temizle'),
                            ),
                        ],
                      ),
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${records.length} reklam alanı'
                          '${missingCount > 0 ? ' • $missingCount alanın fiyatı eksik' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: missingCount > 0
                                ? AppColors.warning
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Yalnızca liste kısmı kayar
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
                                    Icons.sell_outlined,
                                    size: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    widget.store.adSpaces.isEmpty
                                        ? 'Önce Reklam Alanları bölümünden alan ekleyin.'
                                        : 'Filtreye uyan reklam alanı bulunamadı.',
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

/// Fiyat girişi isteğe bağlıdır. Boş bırakılan fiyatlar 0 olarak kaydedilir.
class _PriceFormDialog extends StatefulWidget {
  const _PriceFormDialog({required this.store, required this.spaces});

  final AppStore store;
  final List<AdSpaceModel> spaces;

  @override
  State<_PriceFormDialog> createState() => _PriceFormDialogState();
}

class _PriceFormDialogState extends State<_PriceFormDialog> {
  final TextEditingController _monthly = TextEditingController();
  final TextEditingController _three = TextEditingController();
  final TextEditingController _six = TextEditingController();
  final TextEditingController _twelve = TextEditingController();
  int _index = 0;
  bool _saving = false;
  String? _error;

  AdSpaceModel get _space => widget.spaces[_index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _monthly.dispose();
    _three.dispose();
    _six.dispose();
    _twelve.dispose();
    super.dispose();
  }

  String _format(double? value) {
    if (value == null || value <= 0) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _load() {
    final price = widget.store.adPriceFor(_space.id);
    _monthly.text = _format(price?.monthly);
    _three.text = _format(price?.threeMonth);
    _six.text = _format(price?.sixMonth);
    _twelve.text = _format(price?.twelveMonth);
    _error = null;
  }

  double _parseOrZero(String text) => _parse(text) ?? 0;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.saveAdPrice(
        AdPriceModel(
          id: _space.id,
          adSpaceId: _space.id,
          monthly: _parseOrZero(_monthly.text),
          threeMonth: _parseOrZero(_three.text),
          sixMonth: _parseOrZero(_six.text),
          twelveMonth: _parseOrZero(_twelve.text),
          updatedAt: DateTime.now(),
        ),
      );
      if (_index + 1 >= widget.spaces.length) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      setState(() {
        _index++;
        _load();
        _saving = false;
      });
    } on StateError catch (error) {
      setState(() {
        _error = error.message;
        _saving = false;
      });
    } catch (error) {
      setState(() {
        _error = 'İşlem tamamlanamadı: $error';
        _saving = false;
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool autofocus = false,
    bool last = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixText: '₺',
        ),
        // onFieldSubmitted: last ? (_) => _save() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.spaces.length;
    final multi = total > 1;
    final dialog = AlertDialog(
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      title: SpaceDialogHeader(
        icon: Icons.sell_outlined,
        title: 'Fiyatı düzenle',
        subtitle: multi
            ? '${_index + 1} / $total • ${_space.name}'
            : _space.name,
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (multi) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _index / total,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SpaceSectionTitle(
                text: 'Fiyat listesi',
                icon: Icons.payments_outlined,
              ),
              _field(
                'Aylık fiyat',
                _monthly,
                Icons.calendar_view_month_outlined,
                autofocus: true,
              ),
              _field('3 aylık fiyat', _three, Icons.date_range_outlined),
              _field('6 aylık fiyat', _six, Icons.event_repeat_outlined),
              _field(
                '12 aylık (Yıllık) fiyat',
                _twelve,
                Icons.calendar_month_outlined,
                last: true,
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check_rounded),
          label: Text(
            multi && _index + 1 < total ? 'Kaydet ve devam et' : 'Kaydet',
          ),
        ),
      ],
    );
    return dialog;
  }
}
