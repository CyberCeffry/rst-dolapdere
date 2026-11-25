<#
  yama_fiyat_formlar.ps1

   1) Yeni menu: "Reklam Fiyatlari" - her reklam alani icin Aylik / 3 Aylik / 6 Aylik fiyat.
      * Reklam alanlari normal bolumden cekilir, kiracı bilgisi YOKTUR.
      * Fiyati eksik alan varsa, hepsi girilene kadar kapatilamayan pencere acilir.
      * Fiyatlar ayri bir koleksiyonda tutulur: sozlesme, kiracı, alan duzenleme
        hicbir sekilde bu fiyatlari degistirmez.
      * Ayni ekranda PDF alma (ekrandaki filtre/siralamayla, kiracisiz).
   2) Tum yeni kayit / duzenleme pencerelerinin tasarimi: parlayan ikonlu baslik,
      bolum basliklari, ikonlu Kaydet dugmesi
      (Musteri, Reklam alani, Sozlesme, Rezervasyon, Fiyat).

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_fiyat_formlar.ps1
  Once deneme:  ... -SadeceKontrol
  On kosul: yama_uygula, yama_rezervasyon, yama_uzay_tema, yama_kart_menu uygulanmis olmali.
#>
param(
  [string]$ProjeYolu = (Get-Location).Path,
  [switch]$SadeceKontrol,
  [switch]$AnalizeAtla
)

$ErrorActionPreference = 'Stop'

function N([string]$s) { return ($s -replace "`r`n", "`n") }

$script:buf = @{}
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

$script:failures = New-Object System.Collections.ArrayList
$script:failedFiles = New-Object System.Collections.ArrayList
$script:collect = $true

# Hata toplama modunda listeye ekler (tek seferde hepsini raporlamak icin), degilse firlatir.
function Fail([string]$rel, [string]$msg) {
  if ($script:collect) {
    [void]$script:failures.Add($msg)
    if (-not $script:failedFiles.Contains($rel)) { [void]$script:failedFiles.Add($rel) }
  }
  else { throw $msg }
}

function Edit-Once([string]$rel, [string]$old, [string]$new, [string]$what) {
  $old = N $old; $new = N $new
  $t = $script:buf[$rel]
  $i = $t.IndexOf($old, [StringComparison]::Ordinal)
  if ($i -lt 0) { Fail $rel "[$rel] baglanti noktasi bulunamadi: $what"; return }
  if ($t.IndexOf($old, $i + 1, [StringComparison]::Ordinal) -ge 0) { Fail $rel "[$rel] birden fazla eslesme: $what"; return }
  $script:buf[$rel] = $t.Substring(0, $i) + $new + $t.Substring($i + $old.Length)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

# Kritik olmayan degisiklik: bulunamazsa uyarir, durdurmaz.
function Edit-Optional([string]$rel, [string]$old, [string]$new, [string]$what) {
  $prev = $script:collect
  $script:collect = $false
  try { Edit-Once $rel $old $new $what }
  catch { Write-Host "  ! atlandi (kritik degil): $what" -ForegroundColor Yellow }
  finally { $script:collect = $prev }
}

function Replace-Whole([string]$rel, [string]$marker, [string]$content, [string]$what) {
  if (-not $script:buf[$rel].Contains($marker)) { Fail $rel "[$rel] beklenen surum degil (isaret yok: $marker)"; return }
  $script:buf[$rel] = N $content
  Write-Host "  + $what (dosya yeniden yazildi)" -ForegroundColor DarkGreen
}

# Bir satirlik "anahtar: deger," satirini yeni metinle degistirir (yorumlar atilir).
function Replace-KeyLine([string]$rel, [string]$key, [string]$replacement, [bool]$required) {
  $t = $script:buf[$rel]
  $ms = [regex]::Matches($t, "(?m)^([ \t]*)" + $key + ":[ \t]*([^\n]*)$")
  if ($ms.Count -eq 0) {
    if ($required) { Fail $rel "[$rel] '$key' satiri bulunamadi" }
    return
  }
  if ($ms.Count -gt 1) { Fail $rel "[$rel] '$key' satiri birden fazla"; return }
  $m = $ms[0]
  $code = ($m.Groups[2].Value -replace '//.*$', '').TrimEnd()
  $open = [regex]::Matches($code, '\(').Count
  $close = [regex]::Matches($code, '\)').Count
  if ($open -ne $close -or -not $code.EndsWith(',')) { Fail $rel "[$rel] '$key' degeri tek satirda degil, otomatik yama guvenli degil"; return }
  $indent = $m.Groups[1].Value
  $script:buf[$rel] = $t.Remove($m.Index, $m.Length).Insert($m.Index, ($indent + $replacement))
  Write-Host "  + main: $key -> $replacement" -ForegroundColor DarkGreen
}

# Baslangic baglanti noktasindan bitis baglanti noktasina kadar (bitis HARIC) degistirir.
function Edit-Span([string]$rel, [string]$start, [string]$end, [string]$new, [string]$what) {
  $start = N $start; $end = N $end; $new = N $new
  $t = $script:buf[$rel]
  $i = $t.IndexOf($start, [StringComparison]::Ordinal)
  if ($i -lt 0) { Fail $rel "[$rel] baslangic noktasi bulunamadi: $what"; return }
  if ($t.IndexOf($start, $i + 1, [StringComparison]::Ordinal) -ge 0) { Fail $rel "[$rel] baslangic birden fazla: $what"; return }
  $j = $t.IndexOf($end, $i + $start.Length, [StringComparison]::Ordinal)
  if ($j -lt 0) { Fail $rel "[$rel] bitis noktasi bulunamadi: $what"; return }
  $script:buf[$rel] = $t.Substring(0, $i) + $new + "`n" + $t.Substring($j)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}



# ------------------------------------------------------------------ proje koku
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName } else { Write-Host 'pubspec.yaml bulunamadi.' -ForegroundColor Red; exit 1 }
}
$script:root = $root
Write-Host "Proje: $root" -ForegroundColor Cyan

$F_STORE = 'lib\core\services\app_store.dart'
$F_LAYOUT = 'lib\shared\layouts\main_layout.dart'
$F_SIDEBAR = 'lib\shared\widgets\app_sidebar.dart'
$F_MGMT = 'lib\features\records\management_screens.dart'
$F_RES = 'lib\features\reservations\screens\reservation_screen.dart'

$N_MODEL = 'lib\models\ad_price_model.dart'
$N_FORM = 'lib\shared\widgets\space_form.dart'
$N_PDF = 'lib\features\prices\services\ad_price_pdf_service.dart'
$N_SCREEN = 'lib\features\prices\screens\ad_price_screen.dart'

$adPriceModel = @'
/// Reklam alanı fiyat listesi kaydı. Sözleşmelerden, kiracılardan ve reklam
/// alanının kendi kira alanından TAMAMEN bağımsızdır; yalnızca "Reklam
/// Fiyatları" ekranından değişir. Kimliği, bağlı reklam alanının kimliğidir.
class AdPriceModel {
  const AdPriceModel({
    required this.id,
    required this.adSpaceId,
    required this.monthly,
    required this.threeMonth,
    required this.sixMonth,
    required this.updatedAt,
  });

  final String id;
  final String adSpaceId;
  final double monthly; // Aylık fiyat
  final double threeMonth; // 3 aylık fiyat
  final double sixMonth; // 6 aylık fiyat
  final DateTime updatedAt;

  /// Üç fiyatın da girilmiş olması.
  bool get isComplete => monthly > 0 && threeMonth > 0 && sixMonth > 0;

  factory AdPriceModel.fromJson(Map<String, dynamic> json) => AdPriceModel(
    id: json['id'] as String,
    adSpaceId: json['adSpaceId'] as String? ?? (json['id'] as String),
    monthly: (json['monthly'] as num?)?.toDouble() ?? 0,
    threeMonth: (json['threeMonth'] as num?)?.toDouble() ?? 0,
    sixMonth: (json['sixMonth'] as num?)?.toDouble() ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'adSpaceId': adSpaceId,
    'monthly': monthly,
    'threeMonth': threeMonth,
    'sixMonth': sixMonth,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
'@

$spaceForm = @'
import 'package:flutter/material.dart';

/// Kayıt ekleme/düzenleme pencerelerinin üst başlığı: parlayan ikon kutusu,
/// başlık ve açıklama; arkada camgöbeği → mor geçişli hafif zemin.
/// AlertDialog'da `titlePadding: EdgeInsets.zero` ve `clipBehavior: Clip.antiAlias`
/// ile birlikte kullanılır.
class SpaceDialogHeader extends StatelessWidget {
  const SpaceDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF22D3EE).withValues(alpha: 0.16),
            const Color(0xFF8B5CF6).withValues(alpha: 0.20),
            Colors.transparent,
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formu bölümlere ayıran küçük başlık (ikon + yazı + sönen çizgi).
class SpaceSectionTitle extends StatelessWidget {
  const SpaceSectionTitle({super.key, required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF22D3EE)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF22D3EE).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
'@

$adPricePdf = @'
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../models/ad_space_model.dart';

class AdPricePdfService {
  /// [adSpaces] ekranda o an görünen (filtrelenmiş / sıralanmış) listedir.
  /// Kiracı bilgisi içermez; yalnızca fiyat listesidir.
  static Future<void> exportPrices(
    AppStore store,
    List<AdSpaceModel> adSpaces, {
    String? filterSummary,
  }) async {
    final bytes = await buildPricesPdf(
      store,
      adSpaces,
      filterSummary: filterSummary,
    );
    final fileName =
        'rst-reklam-fiyatlari-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static Future<Uint8List> buildPricesPdf(
    AppStore store,
    List<AdSpaceModel> adSpaces, {
    String? filterSummary,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final dateFormat = DateFormat('dd.MM.yyyy');
    final currency = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    final document = pw.Document(
      title: 'RST Dolapdere Reklam Fiyatları',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı fiyat listesi',
    );

    String money(double value) => value > 0 ? currency.format(value) : '-';

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
                    'RST DOLAPDERE  |  REKLAM FİYATLARI',
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
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.4),
              4: pw.FlexColumnWidth(1.4),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Konum',
                  'Aylık',
                  '3 Aylık',
                  '6 Aylık',
                ],
                boldFont,
                header: true,
              ),
              ...adSpaces.map((space) {
                final price = store.adPriceFor(space.id);
                return _row([
                  space.name,
                  space.location.trim().isEmpty ? '-' : space.location.trim(),
                  money(price?.monthly ?? 0),
                  money(price?.threeMonth ?? 0),
                  money(price?.sixMonth ?? 0),
                ], font);
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
  }) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.blue100)
          : null,
      children: values
          .map(
            (value) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 7,
              ),
              child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 9)),
            ),
          )
          .toList(),
    );
  }
}
'@

$adPriceScreen = @'
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

/// Reklam alanları için aylık / 3 aylık / 6 aylık fiyat listesi.
/// Kiracı bilgisi içermez; sözleşmelerden ve reklam alanı kayıtlarından
/// bağımsızdır, yalnızca bu ekrandan değişir. Fiyatı eksik alan varsa
/// tamamlanana kadar kapatılamayan bir pencere açılır.
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
  bool _forcing = false;

  final NumberFormat _currency = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
  );

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_maybeForce);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeForce());
  }

  @override
  void dispose() {
    widget.store.removeListener(_maybeForce);
    _searchController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fiyatı eksik reklam alanı varsa, hepsi girilene kadar kapanmayan pencereyi açar.
  Future<void> _maybeForce() async {
    if (!mounted || _forcing) return;
    final missing = widget.store.adSpacesMissingPrice;
    if (missing.isEmpty) return;
    _forcing = true;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _PriceFormDialog(store: widget.store, spaces: missing, forced: true),
    );
    _forcing = false;
    if (mounted) _maybeForce();
  }

  Future<void> _edit(AdSpaceModel space) => showDialog<bool>(
    context: context,
    builder: (context) =>
        _PriceFormDialog(store: widget.store, spaces: [space], forced: false),
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
                            'Reklam Fiyatları',
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
                        'Reklam alanları için aylık, 3 aylık ve 6 aylık fiyat listesi '
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
                                : Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Fiyat girişi. [forced] ise (fiyatı eksik alanlar) pencere kapatılamaz ve
/// bütün alanların fiyatı girilene kadar sırayla devam eder.
class _PriceFormDialog extends StatefulWidget {
  const _PriceFormDialog({
    required this.store,
    required this.spaces,
    required this.forced,
  });

  final AppStore store;
  final List<AdSpaceModel> spaces;
  final bool forced;

  @override
  State<_PriceFormDialog> createState() => _PriceFormDialogState();
}

class _PriceFormDialogState extends State<_PriceFormDialog> {
  final TextEditingController _monthly = TextEditingController();
  final TextEditingController _three = TextEditingController();
  final TextEditingController _six = TextEditingController();
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
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
    _formKey = GlobalKey<FormState>();
    _error = null;
  }

  String? _validate(String? value) {
    final number = _parse(value ?? '');
    if (number == null || number <= 0) return 'Fiyat girilmeli (0\'dan büyük).';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.saveAdPrice(
        AdPriceModel(
          id: _space.id,
          adSpaceId: _space.id,
          monthly: _parse(_monthly.text)!,
          threeMonth: _parse(_three.text)!,
          sixMonth: _parse(_six.text)!,
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
      child: TextFormField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixText: '₺',
        ),
        validator: _validate,
        onFieldSubmitted: last ? (_) => _save() : null,
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
        icon: widget.forced ? Icons.priority_high_rounded : Icons.sell_outlined,
        title: widget.forced ? 'Fiyat bilgisi eksik' : 'Fiyatı düzenle',
        subtitle: multi
            ? '${_index + 1} / $total • ${_space.name}'
            : _space.name,
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.forced) ...[
                  Text(
                    multi
                        ? 'Devam etmek için fiyatı eksik $total reklam alanının '
                              'aylık, 3 aylık ve 6 aylık fiyatlarını girin.'
                        : 'Devam etmek için bu reklam alanının aylık, 3 aylık '
                              've 6 aylık fiyatlarını girin.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
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
                _field(
                  '6 aylık fiyat',
                  _six,
                  Icons.event_repeat_outlined,
                  last: true,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!widget.forced)
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
    return widget.forced ? PopScope(canPop: false, child: dialog) : dialog;
  }
}
'@

try {
  foreach ($f in @($F_STORE, $F_LAYOUT, $F_SIDEBAR, $F_MGMT, $F_RES)) { Load-File $f }
  if (-not (Test-Path (Join-Path $root 'lib\shared\widgets\space_hover.dart'))) { throw 'space_hover.dart yok. Once yama_uzay_tema.ps1 uygulanmali.' }
  if ($script:buf[$F_STORE].Contains('AdPriceModel')) {
    Write-Host 'Yama zaten uygulanmis gorunuyor (AdPriceModel mevcut). Durduruldu.' -ForegroundColor Yellow
    exit 0
  }

  # ============================================================ 1) APP STORE
  Write-Host "`n[1] AppStore: reklam fiyatlari (ayri koleksiyon)" -ForegroundColor Cyan
  Edit-Once $F_STORE "import '../../models/reservation_model.dart';" "import '../../models/ad_price_model.dart';`nimport '../../models/reservation_model.dart';" 'import: ad_price_model'
  Edit-Once $F_STORE '  late List<ReservationModel> _reservations;' @'
  late List<ReservationModel> _reservations;
  late List<AdPriceModel> _adPrices;
'@ 'alan: _adPrices'
  Edit-Once $F_STORE @'
    _contracts = _readList('contracts', ContractModel.fromJson);
    _reservations = _readList('reservations', ReservationModel.fromJson);
'@ @'
    _contracts = _readList('contracts', ContractModel.fromJson);
    _reservations = _readList('reservations', ReservationModel.fromJson);
    _adPrices = _readList('adPrices', AdPriceModel.fromJson);
'@ 'yukleme: fiyatlar'
  Edit-Once $F_STORE '  List<ReservationModel> get reservations => List.unmodifiable(_reservations);' @'
  List<ReservationModel> get reservations => List.unmodifiable(_reservations);
  List<AdPriceModel> get adPrices => List.unmodifiable(_adPrices);

  /// Reklam alanının fiyat listesi kaydı (yoksa null).
  AdPriceModel? adPriceFor(String adSpaceId) {
    for (final price in _adPrices) {
      if (price.adSpaceId == adSpaceId) return price;
    }
    return null;
  }

  /// Aylık / 3 aylık / 6 aylık fiyatlarından biri bile girilmemiş reklam alanları.
  List<AdSpaceModel> get adSpacesMissingPrice => _adSpaces
      .where((space) => !(adPriceFor(space.id)?.isComplete ?? false))
      .toList();
'@ 'getter ve yardimcilar'
  Edit-Once $F_STORE @'
    'reservations',
  ];
'@ @'
    'reservations',
    'adPrices',
  ];
'@ 'esitlenen koleksiyonlara ekle'
  Edit-Once $F_STORE "          _differs('reservations', _reservations);" @'
          _differs('reservations', _reservations) ||
          _differs('adPrices', _adPrices);
'@ 'on plana donuste degisiklik kontrolu'
  Edit-Once $F_STORE @'
        _reservations = _readList('reservations', ReservationModel.fromJson);
        _publishSyncStatus();
'@ @'
        _reservations = _readList('reservations', ReservationModel.fromJson);
        _adPrices = _readList('adPrices', AdPriceModel.fromJson);
        _publishSyncStatus();
'@ 'on plana donuste yeniden oku'
  Edit-Once $F_STORE "    'reservations' => _reservations," @'
    'reservations' => _reservations,
    'adPrices' => _adPrices,
'@ '_listFor'
  Edit-Once $F_STORE @'
      case 'reservations':
        _reservations = items.cast<ReservationModel>().toList();
'@ @'
      case 'reservations':
        _reservations = items.cast<ReservationModel>().toList();
      case 'adPrices':
        _adPrices = items.cast<AdPriceModel>().toList();
'@ '_assignList'
  Edit-Once $F_STORE "    'reservations' => ReservationModel.fromJson(json)," @'
    'reservations' => ReservationModel.fromJson(json),
    'adPrices' => AdPriceModel.fromJson(json),
'@ '_decode'
  Edit-Once $F_STORE '  // Rezervasyon ekle/güncelle (reklam alanı başına tek rezervasyon).' @'
  // Reklam fiyatı kaydet. Yalnızca "Reklam Fiyatları" ekranı çağırır; sözleşme,
  // kiracı veya reklam alanı işlemleri bu kayıtlara hiçbir zaman dokunmaz.
  Future<void> saveAdPrice(AdPriceModel price) async {
    if (!_adSpaces.any((space) => space.id == price.adSpaceId)) {
      throw StateError('Reklam alanı bulunamadı.');
    }
    if (!price.isComplete) {
      throw StateError(
        'Aylık, 3 aylık ve 6 aylık fiyatların hepsi girilmelidir.',
      );
    }
    _adPrices = _upsert(_adPrices, price, (item) => item.id);
    await _persistCollection('adPrices', [price]);
    notifyListeners();
  }

  // Rezervasyon ekle/güncelle (reklam alanı başına tek rezervasyon).
'@ 'saveAdPrice'

  # ============================================================ 2) MENU
  Write-Host "`n[2] Menu: Reklam Fiyatlari" -ForegroundColor Cyan
  Edit-Once $F_LAYOUT "import '../../features/reservations/screens/reservation_screen.dart';" "import '../../features/prices/screens/ad_price_screen.dart';`nimport '../../features/reservations/screens/reservation_screen.dart';" 'main_layout: import'
  Edit-Once $F_LAYOUT @'
    'Rezervasyonlar',
  ];
'@ @'
    'Rezervasyonlar',
    'Reklam Fiyatları',
  ];
'@ 'main_layout: sayfa basliklari'
  Edit-Once $F_LAYOUT "    if (_canAccess('reservations')) 7," @'
    if (_canAccess('reservations')) 7,
    if (_canAccess('prices')) 8,
'@ 'main_layout: menu sirasi'
  Edit-Once $F_LAYOUT "      7 => 'reservations'," @'
      7 => 'reservations',
      8 => 'prices',
'@ 'main_layout: modul eslemesi'
  Edit-Once $F_LAYOUT '        return ReservationScreen(store: widget.store);' @'
        return ReservationScreen(store: widget.store);
      case 8:
        return AdPriceScreen(store: widget.store);
'@ 'main_layout: sayfa'
  Edit-Once $F_SIDEBAR @'
    NavigationDestination(
      icon: Icon(Icons.bookmark_border),
      label: 'Rezervasyonlar',
    ),
  ];
'@ @'
    NavigationDestination(
      icon: Icon(Icons.bookmark_border),
      label: 'Rezervasyonlar',
    ),
    NavigationDestination(
      icon: Icon(Icons.sell_outlined),
      label: 'Fiyatlar',
    ),
  ];
'@ 'kenar cubugu: ogesi'
  Edit-Once $F_SIDEBAR @'
    'Rezervasyonlar',
  ];
'@ @'
    'Rezervasyonlar',
    'Reklam Fiyatları',
  ];
'@ 'kenar cubugu: etiket'

  # ============================================================ 3) KAYIT FORMLARI (musteri / alan / sozlesme)
  Write-Host "`n[3] Kayit pencereleri tasarimi" -ForegroundColor Cyan
  Edit-Once $F_MGMT "import '../../shared/widgets/space_hover.dart';" "import '../../shared/widgets/space_form.dart';`nimport '../../shared/widgets/space_hover.dart';" 'management: import space_form'
  Edit-Once $F_MGMT '  String get _title => widget.isRenewal' @'
  IconData get _headerIcon => switch (widget.type) {
    RecordType.adSpaces => Icons.location_city_outlined,
    RecordType.customers => Icons.business_outlined,
    RecordType.contracts =>
      widget.isRenewal ? Icons.autorenew : Icons.description_outlined,
  };

  String get _headerTitle {
    final editing = widget.initial != null && !widget.isRenewal;
    if (widget.isRenewal) return 'Sözleşmeyi uzat';
    return switch (widget.type) {
      RecordType.adSpaces =>
        editing ? 'Reklam alanını düzenle' : 'Yeni reklam alanı',
      RecordType.customers => editing ? 'Müşteriyi düzenle' : 'Yeni müşteri',
      RecordType.contracts =>
        editing ? 'Sözleşmeyi düzenle' : 'Yeni sözleşme',
    };
  }

  String get _headerSubtitle => switch (widget.type) {
    RecordType.adSpaces => 'Alan adı, konum ve açıklama bilgileri',
    RecordType.customers => 'Firma, adres ve iletişim bilgileri',
    RecordType.contracts =>
      widget.isRenewal
          ? 'Yeni süre ve tutarı belirleyin'
          : 'Taraflar, süre ve tutar bilgileri',
  };

  String get _title => widget.isRenewal
'@ 'form: baslik bilgileri'
  Edit-Once $F_MGMT @'
      title: Text(_title),
      content: SizedBox(
        width: 480,
'@ @'
      clipBehavior: Clip.antiAlias,
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      title: SpaceDialogHeader(
        icon: _headerIcon,
        title: _headerTitle,
        subtitle: _headerSubtitle,
      ),
      content: SizedBox(
        width: 480,
'@ 'form: ikonlu baslik'
  Edit-Once $F_MGMT "        FilledButton(onPressed: _save, child: const Text('Kaydet'))," @'
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Kaydet'),
        ),
'@ 'form: Kaydet dugmesi'
  Edit-Once $F_MGMT '  double _parsePrice() =>' @'
  Widget _sectionTitle(String text, IconData icon) =>
      SpaceSectionTitle(text: text, icon: icon);

  double _parsePrice() =>
'@ 'form: bolum basligi yardimcisi'
  Edit-Once $F_MGMT @'
                if (widget.type == RecordType.adSpaces) ...[
                  _textField('Alan adı', _name, required: true),
                  _textField('Konum', _location),
                  _textField(
                    'Aylık kira (₺)',
'@ @'
                if (widget.type == RecordType.adSpaces) ...[
                  _sectionTitle('Alan bilgileri', Icons.location_city_outlined),
                  _textField('Alan adı', _name, required: true),
                  _textField('Konum', _location),
                  _sectionTitle('Kira ve açıklama', Icons.payments_outlined),
                  _textField(
                    'Aylık kira (₺)',
'@ 'alan formu: bolumler'
  Edit-Once $F_MGMT @'
                if (widget.type == RecordType.customers) ...[
                  _textField('Firma adı', _company, required: true),
                  _textField('Adres', _address, maxLines: 2),
                  _textField(
                    'Telefon',
'@ @'
                if (widget.type == RecordType.customers) ...[
                  _sectionTitle('Firma bilgileri', Icons.business_outlined),
                  _textField('Firma adı', _company, required: true),
                  _textField('Adres', _address, maxLines: 2),
                  _sectionTitle('İletişim', Icons.contact_phone_outlined),
                  _textField(
                    'Telefon',
'@ 'musteri formu: bolumler'
  Edit-Once $F_MGMT @'
                if (isContract) ...[
                  SearchablePicker<String>(
                    label: 'Müşteri',
'@ @'
                if (isContract) ...[
                  _sectionTitle('Taraflar', Icons.handshake_outlined),
                  SearchablePicker<String>(
                    label: 'Müşteri',
'@ 'sozlesme formu: Taraflar'
  Edit-Once $F_MGMT @'
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sözleşme süresi',
'@ @'
                  const SizedBox(height: 6),
                  _sectionTitle('Süre ve tarihler', Icons.event_note_outlined),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sözleşme süresi',
'@ 'sozlesme formu: Sure ve tarihler'
  Edit-Once $F_MGMT @'
                  _textField(
                    'Toplam tutar (₺)',
'@ @'
                  _sectionTitle('Tutar ve notlar', Icons.payments_outlined),
                  _textField(
                    'Toplam tutar (₺)',
'@ 'sozlesme formu: Tutar ve notlar'

  # ============================================================ 4) REZERVASYON FORMU
  Write-Host "`n[4] Rezervasyon penceresi tasarimi" -ForegroundColor Cyan
  Edit-Once $F_RES "import '../../../shared/widgets/space_hover.dart';" "import '../../../shared/widgets/space_form.dart';`nimport '../../../shared/widgets/space_hover.dart';" 'rezervasyon: import space_form'
  Edit-Once $F_RES @'
      title: Text(editing ? 'Rezervasyonu düzenle' : 'Yeni rezervasyon'),
      content: SizedBox(
        width: 480,
'@ @'
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
'@ 'rezervasyon: ikonlu baslik'
  Edit-Once $F_RES "FilledButton(onPressed: _save, child: const Text('Kaydet'))," @'
FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Kaydet'),
          ),
'@ 'rezervasyon: Kaydet dugmesi'
  Edit-Once $F_RES @'
                    const SizedBox(height: 4),
                    SearchablePicker<String>(
                      label: 'Reklam alanı',
'@ @'
                    const SpaceSectionTitle(
                      text: 'Alan ve kişi',
                      icon: Icons.handshake_outlined,
                    ),
                    SearchablePicker<String>(
                      label: 'Reklam alanı',
'@ 'rezervasyon: Alan ve kisi'
  Edit-Once $F_RES @'
                    const SizedBox(height: 14),
                    TextField(
                      controller: _notes,
'@ @'
                    const SizedBox(height: 14),
                    const SpaceSectionTitle(
                      text: 'Not',
                      icon: Icons.notes_outlined,
                    ),
                    TextField(
                      controller: _notes,
'@ 'rezervasyon: Not bolumu'

  if ($script:failures.Count -gt 0) {
    $dump = Join-Path ([Environment]::GetFolderPath('Desktop')) 'yama_hata_dosyalari'
    New-Item -ItemType Directory -Force $dump | Out-Null
    foreach ($rel in $script:failedFiles) {
      Copy-Item $script:meta[$rel].Path (Join-Path $dump ([IO.Path]::GetFileName($rel))) -Force
    }
    throw ("Bazi baglanti noktalari bulunamadi (dosyaniz beklenenden farkli):`n  - " + ($script:failures -join "`n  - ") + "`n`nIlgili dosyalarin kopyasi masaustundeki 'yama_hata_dosyalari' klasorune kaydedildi. O dosyalari bana gonderin.")
  }
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

# ------------------------------------------------------------------ yedek (proje DISINA)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$yedekKok = Join-Path (Split-Path $root -Parent) ((Split-Path $root -Leaf) + '_yedekler')
$backup = Join-Path $yedekKok "yedek_$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null
Copy-Item (Join-Path $root 'lib') (Join-Path $backup 'lib') -Recurse -Force
Write-Host "`nYedek alindi: $backup" -ForegroundColor Cyan

foreach ($f in @($F_STORE, $F_LAYOUT, $F_SIDEBAR, $F_MGMT, $F_RES)) {
  Save-File $f
  Write-Host "  yazildi: $f" -ForegroundColor DarkGreen
}
$utf8 = New-Object Text.UTF8Encoding($false)
$newFiles = [ordered]@{}
$newFiles[$N_MODEL] = $adPriceModel
$newFiles[$N_FORM] = $spaceForm
$newFiles[$N_PDF] = $adPricePdf
$newFiles[$N_SCREEN] = $adPriceScreen
foreach ($rel in $newFiles.Keys) {
  $path = Join-Path $root $rel
  New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
  [IO.File]::WriteAllText($path, ($newFiles[$rel] -replace "`r`n", "`n"), $utf8)
  Write-Host "  yeni: $rel" -ForegroundColor DarkGreen
}

if (-not $AnalizeAtla -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "`nflutter analyze calistiriliyor..." -ForegroundColor Cyan
  Push-Location $root
  $ErrorActionPreference = 'Continue'
  try { & flutter analyze --no-pub 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -Last 60 } finally { Pop-Location; $ErrorActionPreference = 'Stop' }
}

Write-Host "`nBITTI. Yedek: $backup" -ForegroundColor Green
Write-Host "Geri almak icin: Copy-Item '$backup\lib\*' '$root\lib' -Recurse -Force" -ForegroundColor DarkGray
