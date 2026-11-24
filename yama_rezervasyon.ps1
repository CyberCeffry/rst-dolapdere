<#
  yama_rezervasyon.ps1

  1) Yeni sozlesme formu: Musteri / Reklam alani secimi artik alanin ALTINDA acilan,
     icinde ARAMA kutusu olan menu; yazi ustten kesilmez (ust bosluk artirildi).
  2) Yeni "Rezervasyonlar" menusu (reklam alani icin sonraki kullanici), PDF cikti.
  3) Reklam alani PDF'inde "Sorumlu" sutunu "Rezerve" olur (rezerve eden musteri).
  4) Reklam alani satirinda "Rezerve: ..." bilgisi.

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_rezervasyon.ps1
  Once deneme (hicbir dosyaya yazmaz):
      powershell -ExecutionPolicy Bypass -File .\yama_rezervasyon.ps1 -SadeceKontrol
  Diger: -ProjeYolu "C:\..."   -AnalizeAtla

  Guvenlik: Tum degisiklikler once bellekte uygulanir; bir baglanti noktasi
  bulunamazsa HICBIR dosya degistirilmez. Yazmadan once lib klasorunun yedegi alinir.
#>
param(
  [string]$ProjeYolu = (Get-Location).Path,
  [switch]$SadeceKontrol,
  [switch]$AnalizeAtla
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------ yardimcilar
function N([string]$s) { return ($s -replace "`r`n", "`n") }

$script:buf  = @{}
$script:meta = @{}

function Load-File([string]$rel) {
  $path = Join-Path $script:root $rel
  if (-not (Test-Path $path)) { throw "Dosya bulunamadi: $rel" }
  $bytes = [IO.File]::ReadAllBytes($path)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  if ($bom) { $text = $text.Substring(1) }
  $script:meta[$rel] = @{ Bom = $bom; Crlf = $text.Contains("`r`n"); Path = $path }
  $script:buf[$rel] = N $text
}

function Save-File([string]$rel) {
  $m = $script:meta[$rel]
  $text = $script:buf[$rel]
  if ($m.Crlf) { $text = $text -replace "`n", "`r`n" }
  [IO.File]::WriteAllText($m.Path, $text, (New-Object Text.UTF8Encoding($m.Bom)))
}

function Edit-Once([string]$rel, [string]$old, [string]$new, [string]$what) {
  $old = N $old; $new = N $new
  $t = $script:buf[$rel]
  $i = $t.IndexOf($old, [StringComparison]::Ordinal)
  if ($i -lt 0) { throw "[$rel] baglanti noktasi bulunamadi: $what" }
  if ($t.IndexOf($old, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "[$rel] birden fazla eslesme: $what" }
  $script:buf[$rel] = $t.Substring(0, $i) + $new + $t.Substring($i + $old.Length)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

# Kritik olmayan degisiklik: bulunamazsa uyarir, durdurmaz.
function Edit-Optional([string]$rel, [string]$old, [string]$new, [string]$what) {
  try { Edit-Once $rel $old $new $what }
  catch { Write-Host "  ! atlandi (kritik degil): $what" -ForegroundColor Yellow }
}

# Baslangic baglanti noktasindan bitis baglanti noktasina kadar (bitis HARIC) degistirir.
function Edit-Span([string]$rel, [string]$start, [string]$end, [string]$new, [string]$what) {
  $start = N $start; $end = N $end; $new = N $new
  $t = $script:buf[$rel]
  $i = $t.IndexOf($start, [StringComparison]::Ordinal)
  if ($i -lt 0) { throw "[$rel] baslangic noktasi bulunamadi: $what" }
  if ($t.IndexOf($start, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "[$rel] baslangic birden fazla: $what" }
  $j = $t.IndexOf($end, $i + $start.Length, [StringComparison]::Ordinal)
  if ($j -lt 0) { throw "[$rel] bitis noktasi bulunamadi: $what" }
  $script:buf[$rel] = $t.Substring(0, $i) + $new + "`n" + $t.Substring($j)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

# --- Kenar cubugu: Bildirimler ogesini kopyalayip sona "Rezervasyonlar" ekler ---
function Find-NavElement([string]$text, [string]$label) {
  $m = [regex]::Match($text, "label:\s*['""]" + [regex]::Escape($label) + "['""]")
  if (-not $m.Success) { throw "app_sidebar: '$label' etiketi bulunamadi" }
  $start = $text.LastIndexOf('NavigationDestination(', $m.Index, [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "app_sidebar: NavigationDestination( bulunamadi ($label)" }
  if ($start -ge 6 -and $text.Substring($start - 6, 6) -eq 'const ') { $start -= 6 }
  $open = $text.IndexOf('(', $start)
  $depth = 0
  for ($k = $open; $k -lt $text.Length; $k++) {
    $c = $text[$k]
    if ($c -eq '(') { $depth++ }
    elseif ($c -eq ')') { $depth--; if ($depth -eq 0) { return @{ Start = $start; End = $k + 1 } } }
  }
  throw "app_sidebar: $label ogesinin kapanisi bulunamadi"
}

function Patch-Sidebar([string]$text) {
  if ($text.Contains('Rezervasyonlar')) { throw 'app_sidebar: Rezervasyonlar zaten var' }
  $bild = Find-NavElement $text 'Bildirimler'
  $ayar = Find-NavElement $text 'Ayarlar'
  if ($ayar.Start -le $bild.Start) { throw 'app_sidebar: beklenen sira (Bildirimler, Ayarlar) degil' }
  $elem = $text.Substring($bild.Start, $bild.End - $bild.Start)
  $inElem = [regex]::Matches($elem, 'Icons\.notifications').Count
  $inFile = [regex]::Matches($text, 'Icons\.notifications').Count
  if ($inElem -lt 1 -or $inFile -ne $inElem) { throw 'app_sidebar: ikon baska bir listede de tanimli, otomatik yama guvenli degil' }

  $clone = $elem -replace 'Icons\.notifications_outlined', 'Icons.bookmark_border'
  $clone = $clone -replace 'Icons\.notifications(?!_)', 'Icons.bookmark'
  $clone = $clone -replace "label:\s*(['""])Bildirimler(['""])", 'label: ''Rezervasyonlar'''
  if (-not $clone.Contains('Rezervasyonlar')) { throw 'app_sidebar: etiket kopyalanamadi' }

  # Satir girintisi
  $lineStart = $text.LastIndexOf("`n", $bild.Start) + 1
  $indent = $text.Substring($lineStart, $bild.Start - $lineStart)
  if ($indent.Trim().Length -ne 0) { $indent = '    ' }

  $pos = $ayar.End
  $after = $text.Substring($pos)
  $comma = [regex]::Match($after, '^[ \t]*,')
  if (-not $comma.Success) { throw 'app_sidebar: Ayarlar ogesinden sonra virgul beklenirdi' }
  $pos += $comma.Length
  $text = $text.Insert($pos, "`n" + $indent + $clone + ',')

  # Ayri bir "etiket listesi" varsa ('Bildirimler', 'Ayarlar' tek satirlik metinler)
  $labelRe = "(?m)^([ \t]*)['""]Bildirimler['""],[ \t]*(//.*)?$"
  $found = [regex]::Matches($text, $labelRe)
  if ($found.Count -gt 1) { throw 'app_sidebar: birden fazla etiket listesi var, otomatik yama guvenli degil' }
  if ($found.Count -eq 1) {
    $from = $found[0].Index + $found[0].Length
    $am = [regex]::Match($text.Substring($from), "(?m)^([ \t]*)['""]Ayarlar['""],[ \t]*(//.*)?$")
    if (-not $am.Success) { throw 'app_sidebar: etiket listesinde Ayarlar satiri bulunamadi' }
    $insertAt = $from + $am.Index + $am.Length
    $text = $text.Insert($insertAt, "`n" + $am.Groups[1].Value + "'Rezervasyonlar',")
  }
  return $text
}

# ------------------------------------------------------------------ proje koku
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName } else { Write-Host 'pubspec.yaml bulunamadi.' -ForegroundColor Red; exit 1 }
}
$script:root = $root
Write-Host "Proje: $root" -ForegroundColor Cyan

$F_MGMT    = 'lib\features\records\management_screens.dart'
$F_ADPDF   = 'lib\features\records\services\ad_space_pdf_service.dart'
$F_STORE   = 'lib\core\services\app_store.dart'
$F_LAYOUT  = 'lib\shared\layouts\main_layout.dart'
$F_SIDEBAR = 'lib\shared\widgets\app_sidebar.dart'
$F_REM     = 'lib\core\utils\contract_remaining_time.dart'
$F_TRTEXT  = 'lib\core\utils\turkish_text.dart'

$N_MODEL  = 'lib\models\reservation_model.dart'
$N_PICKER = 'lib\shared\widgets\searchable_picker.dart'
$N_SCREEN = 'lib\features\reservations\screens\reservation_screen.dart'
$N_PDF    = 'lib\features\reservations\services\reservation_pdf_service.dart'

$reservationModel = @'
/// Bir reklam alanı için, mevcut kiracıdan sonraki kullanıcı adına yapılan rezervasyon.
class ReservationModel {
  const ReservationModel({
    required this.id,
    required this.adSpaceId,
    required this.customerId,
    required this.createdAt,
    this.notes = '',
  });

  final String id;
  final String adSpaceId; // Rezerve edilen reklam alanı
  final String customerId; // Rezerve eden (sıradaki) müşteri
  final DateTime createdAt; // Rezervasyonun yapıldığı tarih
  final String notes;

  factory ReservationModel.fromJson(Map<String, dynamic> json) =>
      ReservationModel(
        id: json['id'] as String,
        adSpaceId: json['adSpaceId'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'adSpaceId': adSpaceId,
    'customerId': customerId,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
  };
}
'@

$searchablePicker = @'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/turkish_text.dart';

/// [SearchablePicker] listesindeki bir seçenek.
class PickerItem<T> {
  const PickerItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.searchText = '',
  });

  final T value;
  final String label;
  final String? subtitle; // Seçenek altında küçük yazı
  final String searchText; // Aramada ek olarak taranan metin
}

/// Alanın hemen altında açılan, içinde arama kutusu bulunan seçim menüsü.
/// Yer yoksa yukarı doğru açılır; liste yüksekliği sınırlıdır ve kendi içinde kayar.
/// Arama büyük/küçük harf ve Türkçe karakter (ş, ı, ğ...) duyarsızdır.
class SearchablePicker<T> extends StatefulWidget {
  const SearchablePicker({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.searchHint = 'Ara...',
    this.emptyText = 'Sonuç bulunamadı',
  });

  final String label;
  final List<PickerItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? errorText;
  final String searchHint;
  final String emptyText;

  @override
  State<SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<SearchablePicker<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode();
  OverlayEntry? _entry;
  String _query = '';

  bool get _isOpen => _entry != null;

  List<PickerItem<T>> get _filtered {
    final query = TurkishText.fold(_query.trim());
    if (query.isEmpty) return widget.items;
    return widget.items
        .where(
          (item) => TurkishText.fold(
            '${item.label} ${item.subtitle ?? ''} ${item.searchText}',
          ).contains(query),
        )
        .toList();
  }

  void _open() {
    if (_isOpen) return;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final spaceBelow = screen.height - (origin.dy + size.height) - 16;
    final spaceAbove = origin.dy - 16;
    final openUp = spaceBelow < 230 && spaceAbove > spaceBelow;
    final maxHeight = (openUp ? spaceAbove : spaceBelow).clamp(150.0, 380.0);

    _search.clear();
    _query = '';
    _entry = OverlayEntry(
      builder: (context) => _buildOverlay(size.width, openUp, maxHeight),
    );
    Overlay.of(context).insert(_entry!);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOpen) _focus.requestFocus();
    });
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

  void _select(PickerItem<T> item) {
    widget.onChanged(item.value);
    _close();
  }

  Widget _buildOverlay(double width, bool openUp, double maxHeight) {
    final items = _filtered;
    final theme = Theme.of(context);
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
          targetAnchor: openUp ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: openUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, openUp ? -4 : 4),
          child: SizedBox(
            width: width,
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                          child: TextField(
                            controller: _search,
                            focusNode: _focus,
                            decoration: InputDecoration(
                              hintText: widget.searchHint,
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                            ),
                            onChanged: (value) {
                              _query = value;
                              _entry?.markNeedsBuild();
                            },
                            onSubmitted: (_) {
                              final current = _filtered;
                              if (current.isNotEmpty) _select(current.first);
                            },
                          ),
                        ),
                        Flexible(
                          child: items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    widget.emptyText,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.only(bottom: 6),
                                  itemCount: items.length,
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    final selected = item.value == widget.value;
                                    return ListTile(
                                      dense: true,
                                      selected: selected,
                                      title: Text(
                                        item.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: item.subtitle == null
                                          ? null
                                          : Text(
                                              item.subtitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                      trailing: selected
                                          ? const Icon(Icons.check, size: 18)
                                          : null,
                                      onTap: () => _select(item),
                                    );
                                  },
                                ),
                        ),
                      ],
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
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PickerItem<T>? selected;
    for (final item in widget.items) {
      if (item.value == widget.value) {
        selected = item;
        break;
      }
    }
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        key: _fieldKey,
        onTap: _isOpen ? _close : _open,
        child: InputDecorator(
          isFocused: _isOpen,
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: widget.errorText,
            isDense: false,
            // Üst boşluk biraz fazla: yazı üstten kesilmez, daha aşağıda durur.
            contentPadding: const EdgeInsets.fromLTRB(14, 22, 8, 14),
            suffixIcon: Icon(
              _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            ),
          ),
          child: Text(
            selected?.label ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
'@

$reservationScreen = @'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../models/reservation_model.dart';
import '../../../shared/widgets/searchable_picker.dart';
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

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.bookmark_border, color: AppColors.primary),
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
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _openForm(reservation);
            if (value == 'delete') _delete(reservation);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Düzenle')),
            PopupMenuItem(value: 'delete', child: Text('Sil')),
          ],
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
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            24,
          ),
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
      title: Text(editing ? 'Rezervasyonu düzenle' : 'Yeni rezervasyon'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: nothingToReserve
              ? const Text('Tüm reklam alanları için zaten rezervasyon var.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    SearchablePicker<String>(
                      label: 'Reklam alanı',
                      value: _adSpaceId,
                      items: spaces,
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
                      onChanged: (value) =>
                          setState(() => _customerId = value),
                    ),
                    const SizedBox(height: 14),
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
          FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
'@

$reservationPdf = @'
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../models/reservation_model.dart';

class ReservationPdfService {
  /// [reservations] ekranda o an görünen (filtrelenmiş / sıralanmış) listedir;
  /// PDF bu sırayı aynen kullanır.
  static Future<void> exportReservations(
    AppStore store,
    List<ReservationModel> reservations, {
    String? filterSummary,
  }) async {
    final bytes = await buildReservationsPdf(
      store,
      reservations,
      filterSummary: filterSummary,
    );
    final fileName =
        'rst-rezervasyonlar-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static Future<Uint8List> buildReservationsPdf(
    AppStore store,
    List<ReservationModel> reservations, {
    String? filterSummary,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final dateFormat = DateFormat('dd.MM.yyyy');
    final currencyFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    final document = pw.Document(
      title: 'RST Dolapdere Rezervasyonlar',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı rezervasyonları',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'RST DOLAPDERE  |  REZERVASYONLAR',
                    style: pw.TextStyle(font: boldFont, fontSize: 16),
                  ),
                  pw.Text('Dışa aktarma: ${dateFormat.format(DateTime.now())}'),
                ],
              ),
              if (filterSummary != null && filterSummary.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(
                    'Filtre: $filterSummary',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${context.pageNumber} / ${context.pagesCount}'),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(1.5),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Rezerve eden',
                  'Mevcut kiracı',
                  'Kalan süre',
                  'Verilen tutar',
                ],
                boldFont,
                header: true,
              ),
              ...reservations.map((reservation) {
                final space = store.adSpaceFor(reservation.adSpaceId);
                final reserver = store.customerFor(reservation.customerId);
                final contract = store.activeContractForAdSpace(
                  reservation.adSpaceId,
                );
                final tenant = contract == null
                    ? null
                    : store.customerFor(contract.customerId);
                final isEmpty = contract == null;
                final days = contract == null
                    ? null
                    : ContractRemainingTime.daysUntil(contract.endDate);
                return _row(
                  [
                    space?.name ?? 'Reklam alanı',
                    reserver?.name ?? 'Müşteri',
                    isEmpty ? 'Kiracı yok' : (tenant?.name ?? 'Bilinmiyor'),
                    contract == null
                        ? '-'
                        : ContractRemainingTime.formatDetailed(
                            contract.endDate,
                          ),
                    contract == null
                        ? '-'
                        : currencyFormat.format(contract.monthlyPrice),
                  ],
                  font,
                  empty: isEmpty,
                  remainingColor:
                      days != null && ContractRemainingTime.isUrgent(days)
                      ? PdfColors.red
                      : null,
                );
              }),
            ],
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.TableRow _row(
    List<String> values,
    pw.Font font, {
    bool header = false,
    bool empty = false,
    PdfColor? remainingColor,
  }) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.grey200)
          : empty
          ? const pw.BoxDecoration(color: PdfColors.yellow100)
          : null,
      children: values.indexed.map((entry) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: pw.Text(
            entry.$2,
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: entry.$1 == 3 ? remainingColor : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}
'@

try {
  if (-not (Test-Path (Join-Path $root $F_TRTEXT))) { throw "turkish_text.dart yok. Once ilk yama (yama_uygula.ps1) uygulanmali." }
  foreach ($f in @($F_MGMT, $F_ADPDF, $F_STORE, $F_LAYOUT, $F_SIDEBAR, $F_REM)) { Load-File $f }
  if ($script:buf[$F_STORE].Contains('ReservationModel')) {
    Write-Host 'Yama zaten uygulanmis gorunuyor (ReservationModel mevcut). Durduruldu.' -ForegroundColor Yellow
    exit 0
  }

  # ============================================================ 0) Ayrintili kalan sure (yoksa ekle)
  if (-not $script:buf[$F_REM].Contains('formatDetailed')) {
    Write-Host "`n[0] ContractRemainingTime.formatDetailed (eksikti, ekleniyor)" -ForegroundColor Cyan
    Edit-Once $F_REM '  static bool isUrgent(int days) => days >= 0 && days < 15;' @'
  static bool isUrgent(int days) => days >= 0 && days < 15;

  /// Ayrıntılı kalan süre: "25 gün", "1 ay 8 gün", "3 ay".
  static String formatDetailed(DateTime endDate, {DateTime? today}) {
    final days = daysUntil(endDate, today: today);
    if (days <= 30) return '$days gün';
    final now = today ?? DateTime.now();
    final start = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    var months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day < start.day) months--;
    if (months < 1) return '$days gün';
    final anchorMonth = start.month + months;
    final lastDay = DateTime.utc(start.year, anchorMonth + 1, 0).day;
    final anchor = DateTime.utc(
      start.year,
      anchorMonth,
      start.day > lastDay ? lastDay : start.day,
    );
    final extraDays = end.difference(anchor).inDays;
    return extraDays > 0 ? '$months ay $extraDays gün' : '$months ay';
  }
'@ 'formatDetailed'
  }

  # ============================================================ 1) APP STORE
  Write-Host "`n[1] AppStore (rezervasyon verisi + esitleme)" -ForegroundColor Cyan
  Edit-Once $F_STORE "import '../../models/customer_model.dart';" "import '../../models/reservation_model.dart';`nimport '../../models/customer_model.dart';" 'import: reservation_model'
  Edit-Once $F_STORE '  late List<ContractModel> _contracts;' @'
  late List<ContractModel> _contracts;
  late List<ReservationModel> _reservations;
'@ 'alan: _reservations'
  Edit-Once $F_STORE @'
    _adSpaces = _readList('adSpaces', AdSpaceModel.fromJson);
    _contracts = _readList('contracts', ContractModel.fromJson);
'@ @'
    _adSpaces = _readList('adSpaces', AdSpaceModel.fromJson);
    _contracts = _readList('contracts', ContractModel.fromJson);
    _reservations = _readList('reservations', ReservationModel.fromJson);
'@ 'yukleme: rezervasyonlar'
  Edit-Once $F_STORE '  List<ContractModel> get contracts => List.unmodifiable(_contracts);' @'
  List<ContractModel> get contracts => List.unmodifiable(_contracts);
  List<ReservationModel> get reservations => List.unmodifiable(_reservations);

  /// Reklam alanı için bekleyen rezervasyon (yoksa null).
  ReservationModel? reservationForAdSpace(String adSpaceId) {
    for (final reservation in _reservations) {
      if (reservation.adSpaceId == adSpaceId) return reservation;
    }
    return null;
  }

  /// Reklam alanını rezerve eden müşterinin adı (rezervasyon yoksa null).
  String? reservedByNameFor(String adSpaceId) {
    final reservation = reservationForAdSpace(adSpaceId);
    if (reservation == null) return null;
    return customerFor(reservation.customerId)?.name ?? 'Müşteri';
  }
'@ 'getter ve yardimcilar'
  Edit-Once $F_STORE @'
    'contracts',
  ];
'@ @'
    'contracts',
    'reservations',
  ];
'@ 'esitlenen koleksiyonlara ekle'
  Edit-Once $F_STORE "          _differs('contracts', _contracts);" @'
          _differs('contracts', _contracts) ||
          _differs('reservations', _reservations);
'@ 'on plana donuste degisiklik kontrolu'
  Edit-Once $F_STORE @'
        _contracts = _readList('contracts', ContractModel.fromJson);
        _publishSyncStatus();
'@ @'
        _contracts = _readList('contracts', ContractModel.fromJson);
        _reservations = _readList('reservations', ReservationModel.fromJson);
        _publishSyncStatus();
'@ 'on plana donuste yeniden oku'
  Edit-Once $F_STORE @'
    'adSpaces' => _adSpaces,
    _ => _contracts,
'@ @'
    'adSpaces' => _adSpaces,
    'reservations' => _reservations,
    _ => _contracts,
'@ '_listFor'
  Edit-Once $F_STORE @'
      case 'adSpaces':
        _adSpaces = items.cast<AdSpaceModel>().toList();
      default:
'@ @'
      case 'adSpaces':
        _adSpaces = items.cast<AdSpaceModel>().toList();
      case 'reservations':
        _reservations = items.cast<ReservationModel>().toList();
      default:
'@ '_assignList'
  Edit-Once $F_STORE @'
    'adSpaces' => AdSpaceModel.fromJson(json),
    _ => ContractModel.fromJson(json),
'@ @'
    'adSpaces' => AdSpaceModel.fromJson(json),
    'reservations' => ReservationModel.fromJson(json),
    _ => ContractModel.fromJson(json),
'@ '_decode'
  Edit-Once $F_STORE '    _customers.removeWhere((customer) => customer.id == id);' @'
    if (_reservations.any((item) => item.customerId == id)) {
      throw StateError(
        'Bu müşteriye ait rezervasyon var. Önce rezervasyonu silin.',
      );
    }

    _customers.removeWhere((customer) => customer.id == id);
'@ 'musteri silme: rezervasyon kontrolu'
  Edit-Once $F_STORE '    _adSpaces.removeWhere((space) => space.id == id);' @'
    if (_reservations.any((item) => item.adSpaceId == id)) {
      throw StateError(
        'Bu reklam alanı için rezervasyon var. Önce rezervasyonu silin.',
      );
    }

    _adSpaces.removeWhere((space) => space.id == id);
'@ 'alan silme: rezervasyon kontrolu'
  Edit-Once $F_STORE @'
  // Sözleşme sil.
  Future<void> deleteContract(String id) async {
'@ @'
  // Rezervasyon ekle/güncelle (reklam alanı başına tek rezervasyon).
  Future<void> saveReservation(ReservationModel reservation) async {
    if (!_adSpaces.any((space) => space.id == reservation.adSpaceId)) {
      throw StateError('Reklam alanı bulunamadı.');
    }
    if (!_customers.any((customer) => customer.id == reservation.customerId)) {
      throw StateError('Müşteri bulunamadı.');
    }
    if (_reservations.any(
      (item) =>
          item.id != reservation.id && item.adSpaceId == reservation.adSpaceId,
    )) {
      throw StateError(
        'Bu reklam alanı için zaten bir rezervasyon var. '
        'Önce mevcut rezervasyonu düzenleyin veya silin.',
      );
    }
    _reservations = _upsert(_reservations, reservation, (item) => item.id);
    await _persistCollection('reservations', [reservation]);
    notifyListeners();
  }

  // Rezervasyon sil.
  Future<void> deleteReservation(String id) async {
    _reservations.removeWhere((item) => item.id == id);
    await _saveList('reservations', _reservations);
    unawaited(_deleteRemote('reservations', id));
    notifyListeners();
  }

  // Sözleşme sil.
  Future<void> deleteContract(String id) async {
'@ 'saveReservation / deleteReservation'

  # ============================================================ 2) ANA DUZEN + KENAR CUBUGU
  Write-Host "`n[2] Menu: Rezervasyonlar" -ForegroundColor Cyan
  Edit-Once $F_LAYOUT "import '../../features/records/management_screens.dart';" "import '../../features/records/management_screens.dart';`nimport '../../features/reservations/screens/reservation_screen.dart';" 'main_layout: import'
  Edit-Once $F_LAYOUT @'
    'Bildirimler',
    'Ayarlar',
  ];
'@ @'
    'Bildirimler',
    'Ayarlar',
    'Rezervasyonlar',
  ];
'@ 'main_layout: sayfa basliklari'
  Edit-Once $F_LAYOUT "    if (_canAccess('contracts')) ...[3, 4]," @'
    if (_canAccess('contracts')) ...[3, 4],
    if (_canAccess('reservations')) 7,
'@ 'main_layout: menu sirasi (Biten Sozlesmeler''den sonra)'
  Edit-Once $F_LAYOUT @'
      6 => 'settings',
      _ => null,
'@ @'
      6 => 'settings',
      7 => 'reservations',
      _ => null,
'@ 'main_layout: modul eslemesi'
  Edit-Once $F_LAYOUT @'
      case 6:
        return SettingsScreen(store: widget.store);
'@ @'
      case 6:
        return SettingsScreen(store: widget.store);
      case 7:
        return ReservationScreen(store: widget.store);
'@ 'main_layout: sayfa'

  try {
    $script:buf[$F_SIDEBAR] = Patch-Sidebar $script:buf[$F_SIDEBAR]
    Write-Host '  + app_sidebar: Rezervasyonlar ogesi (Bildirimler ogesi kopyalandi)' -ForegroundColor DarkGreen
  }
  catch {
    $copy = Join-Path ([Environment]::GetFolderPath('Desktop')) 'app_sidebar_kopya.txt'
    [IO.File]::WriteAllText($copy, $script:buf[$F_SIDEBAR], (New-Object Text.UTF8Encoding($true)))
    throw ("Kenar cubugu otomatik yamalanamadi: " + $_.Exception.Message + "`n  -> app_sidebar.dart kopyasi masaustune kaydedildi: $copy`n  -> O dosyayi bana gonderin, ona gore yama yazarim.")
  }

  # ============================================================ 3) YENI SOZLESME FORMU
  Write-Host "`n[3] Yeni sozlesme formu: aramali secim menuleri" -ForegroundColor Cyan
  Edit-Once $F_MGMT "import '../../core/utils/turkish_text.dart';" "import '../../core/utils/turkish_text.dart';`nimport '../../shared/widgets/searchable_picker.dart';" 'import: searchable_picker'
  Edit-Span $F_MGMT @'
                  DropdownButtonFormField<String>(
                    initialValue: _customerId,
'@ @'
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sözleşme süresi',
'@ @'
                  SearchablePicker<String>(
                    label: 'Müşteri',
                    value: _customerId,
                    items: [
                      for (final item in widget.store.customers)
                        PickerItem<String>(
                          value: item.id,
                          label: item.name,
                          subtitle: item.phone.isEmpty ? null : item.phone,
                          searchText:
                              '${item.company} ${item.address} ${item.email}',
                        ),
                    ],
                    onChanged: (value) => setState(() => _customerId = value),
                  ),
                  const SizedBox(height: 14),
                  SearchablePicker<String>(
                    label: 'Reklam alanı',
                    value: _adSpaceId,
                    items: [
                      for (final item in widget.store.adSpaces)
                        PickerItem<String>(
                          value: item.id,
                          label: item.name,
                          subtitle: item.location.isEmpty ? null : item.location,
                          searchText: item.description,
                        ),
                    ],
                    onChanged: (value) => setState(() => _adSpaceId = value),
                  ),
'@ 'musteri + reklam alani secicileri'

  Edit-Optional $F_MGMT "      subtitle = contract == null ? 'Kiracı yok' : '';" @'
      final reservedBy = widget.store.reservedByNameFor(record.id);
      subtitle = contract == null
          ? 'Kiracı yok${reservedBy == null ? '' : '\nRezerve: $reservedBy'}'
          : '';
'@ 'reklam alani satiri: rezerve bilgisi (bos alan)'
  Edit-Optional $F_MGMT @'
              TextSpan(
                text: ContractRemainingTime.format(days!),
                style: remainingStyle,
              ),
'@ @'
              TextSpan(
                text: ContractRemainingTime.format(days!),
                style: remainingStyle,
              ),
              if (reservedBy != null)
                TextSpan(text: '\nRezerve: $reservedBy'),
'@ 'reklam alani satiri: rezerve bilgisi (kirada)'

  # ============================================================ 4) ALAN PDF
  Write-Host "`n[4] Reklam alani PDF: Sorumlu -> Rezerve" -ForegroundColor Cyan
  Edit-Once $F_ADPDF "'Sorumlu'," "'Rezerve'," 'baslik: Rezerve'
  Edit-Once $F_ADPDF "contract?.responsibleUsername ?? '-'," "store.reservedByNameFor(space.id) ?? '-'," 'hucre: rezerve eden musteri'

  Write-Host "`nTum baglanti noktalari dogrulandi." -ForegroundColor Green
}
catch {
  Write-Host "`nHATA: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Hicbir dosya degistirilmedi.' -ForegroundColor Yellow
  exit 1
}

if ($SadeceKontrol) {
  Write-Host "`n-SadeceKontrol: dosyalara yazilmadi." -ForegroundColor Yellow
  exit 0
}

# ------------------------------------------------------------------ yedek
$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $root "_yedek_$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null
Copy-Item (Join-Path $root 'lib') (Join-Path $backup 'lib') -Recurse -Force
Write-Host "`nYedek alindi: $backup" -ForegroundColor Cyan

# ------------------------------------------------------------------ yazma
foreach ($f in @($F_MGMT, $F_ADPDF, $F_STORE, $F_LAYOUT, $F_SIDEBAR, $F_REM)) {
  Save-File $f
  Write-Host "  yazildi: $f" -ForegroundColor DarkGreen
}
$utf8 = New-Object Text.UTF8Encoding($false)
$newFiles = [ordered]@{}
$newFiles[$N_MODEL]  = $reservationModel
$newFiles[$N_PICKER] = $searchablePicker
$newFiles[$N_SCREEN] = $reservationScreen
$newFiles[$N_PDF]    = $reservationPdf
foreach ($rel in $newFiles.Keys) {
  $path = Join-Path $root $rel
  New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
  [IO.File]::WriteAllText($path, ($newFiles[$rel] -replace "`r`n", "`n"), $utf8)
  Write-Host "  yeni: $rel" -ForegroundColor DarkGreen
}

# ------------------------------------------------------------------ analiz
if (-not $AnalizeAtla -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "`nflutter analyze calistiriliyor..." -ForegroundColor Cyan
  Push-Location $root
  $ErrorActionPreference = 'Continue'
  try { & flutter analyze --no-pub 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -Last 60 } finally { Pop-Location; $ErrorActionPreference = 'Stop' }
}

Write-Host "`nBITTI. Yedek: $backup" -ForegroundColor Green
Write-Host "Geri almak icin: Copy-Item '$backup\lib\*' '$root\lib' -Recurse -Force" -ForegroundColor DarkGray
