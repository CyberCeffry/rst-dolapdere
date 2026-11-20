<#
  yama_uygula.ps1  -  RST Dolapdere (dere_sozlesme_takip) yamasi

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_uygula.ps1
  Once sadece deneme (hicbir dosya yazmaz):
      powershell -ExecutionPolicy Bypass -File .\yama_uygula.ps1 -SadeceKontrol
  Diger anahtarlar:
      -ProjeYolu "C:\...\rst-dolapdere"   -PaketEklemeyiAtla   -AnalizeAtla

  Guvenlik:
   * Once lib + pubspec yedegi alinir  (proje\_yedek_ZAMAN klasoru)
   * Tum degisiklikler once bellekte uygulanir. Bir baglanti noktasi bulunamazsa
     HICBIR dosya degistirilmeden durur.
   * Geri almak icin yedek klasorundeki lib'i projedeki lib'in ustune kopyalayin.
#>
param(
  [string]$ProjeYolu = (Get-Location).Path,
  [switch]$SadeceKontrol,
  [switch]$PaketEklemeyiAtla,
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

function Edit-All([string]$rel, [string]$old, [string]$new, [string]$what) {
  $t = $script:buf[$rel]
  if (-not $t.Contains($old)) { throw "[$rel] bulunamadi: $what" }
  $script:buf[$rel] = $t.Replace($old, $new)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

function Replace-Whole([string]$rel, [string]$marker, [string]$content, [string]$what) {
  if (-not $script:buf[$rel].Contains($marker)) { throw "[$rel] beklenen surum degil (isaret yok: $marker)" }
  $script:buf[$rel] = N $content
  Write-Host "  + $what (dosya yeniden yazildi)" -ForegroundColor DarkGreen
}

# ------------------------------------------------------------------ proje koku
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName } else { Write-Host "pubspec.yaml bulunamadi." -ForegroundColor Red; exit 1 }
}
$script:root = $root
Write-Host "Proje: $root" -ForegroundColor Cyan

$F_MGMT   = 'lib\features\records\management_screens.dart'
$F_NOTIF  = 'lib\features\notifications\screens\notification_screen.dart'
$F_PDF    = 'lib\features\contracts\services\contract_pdf_service.dart'
$F_CUST   = 'lib\models\customer_model.dart'
$F_STORE  = 'lib\core\services\app_store.dart'
$F_MAIN   = 'lib\main.dart'
$F_SET    = 'lib\features\settings\screens\settings_screen.dart'
$F_TRTXT  = 'lib\core\utils\turkish_text.dart'
$F_BGSYNC = 'lib\core\services\background_sync.dart'

try {
  foreach ($f in @($F_MGMT, $F_NOTIF, $F_PDF, $F_CUST, $F_STORE, $F_MAIN, $F_SET)) { Load-File $f }
  if ($script:buf[$F_MGMT].Contains('EndedContractFilter')) {
    Write-Host "Yama zaten uygulanmis gorunuyor (EndedContractFilter mevcut). Durduruldu." -ForegroundColor Yellow
    exit 0
  }

  # ============================================================ 1) MODEL
  Write-Host "`n[1] Musteri modeli (adres alani)" -ForegroundColor Cyan
  $customerModel = @'
class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.name,
    this.company = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.notes = '',
  });

  /// Görünen ad. Artık firma adıyla aynı tutulur (eski kayıtlarda kişi adı olabilir).
  final String id;
  final String name;
  final String company;
  final String address;
  final String phone;
  final String email;
  final String notes;

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    company: json['company'] as String? ?? '',
    address: json['address'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'address': address,
    'phone': phone,
    'email': email,
    'notes': notes,
  };
}
'@
  Replace-Whole $F_CUST 'class CustomerModel' $customerModel 'CustomerModel.address'

  # ============================================================ 2) TURKCE METIN
  $turkishText = @'
/// Türkçe harf duyarlı sıralama ve arama yardımcıları.
class TurkishText {
  static const _alphabet = 'abcçdefgğhıijklmnoöprsştuüvwxyz';

  /// Türkçe kurallarıyla küçük harfe çevirir (I→ı, İ→i).
  static String lower(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      switch (char) {
        case 'I':
          buffer.write('ı');
        case 'İ':
          buffer.write('i');
        default:
          buffer.write(char.toLowerCase());
      }
    }
    return buffer.toString();
  }

  /// Arama için: küçük harf + Türkçe karakterleri sadeleştirir (ş→s, ı→i ...).
  static String fold(String value) {
    const map = {
      'ı': 'i',
      'ş': 's',
      'ç': 'c',
      'ğ': 'g',
      'ö': 'o',
      'ü': 'u',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };
    final buffer = StringBuffer();
    for (final rune in lower(value).runes) {
      final char = String.fromCharCode(rune);
      buffer.write(map[char] ?? char);
    }
    return buffer.toString();
  }

  static int _rank(String char) {
    final index = _alphabet.indexOf(char);
    if (index >= 0) return index + 100;
    final code = char.codeUnitAt(0);
    return code < 100 ? code : code + 1000;
  }

  /// A→Z sıralama karşılaştırıcısı (Ç, Ğ, İ, Ö, Ş, Ü doğru yerde).
  static int compare(String a, String b) {
    final x = lower(a).trim();
    final y = lower(b).trim();
    final length = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < length; i++) {
      final rx = _rank(x[i]);
      final ry = _rank(y[i]);
      if (rx != ry) return rx.compareTo(ry);
    }
    return x.length.compareTo(y.length);
  }
}
'@

  # ============================================================ 3) ARKA PLAN ESITLEME
  $bgSync = @'
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../firebase_options.dart';
import 'app_store.dart';

const String _uniqueName = 'rst_periodic_sync';
const String _taskName = 'rst_periodic_sync_task';
const String _scheduledKey = 'bgSyncScheduledMinutes';

/// Android arka plan görevi (WorkManager) giriş noktası.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final firestore = FirebaseFirestore.instance;
      try {
        firestore.settings = const Settings(persistenceEnabled: false);
      } catch (_) {}
      return await AppStore.runBackgroundSync(firestore);
    } catch (error) {
      debugPrint('Arka plan eşitleme hatası: $error');
      return false;
    }
  });
}

/// Uygulama kapalıyken / arka plandayken de seçilen süreye göre eşitleme.
/// Yalnızca Android'de çalışır (WorkManager en az 15 dakika destekler).
/// Windows'ta uygulama açık olduğu sürece mevcut zamanlayıcı çalışır.
class BackgroundSync {
  static bool get supported => !kIsWeb && Platform.isAndroid;
  static bool _initialized = false;

  static Future<void> schedule(int minutes, {bool force = false}) async {
    if (!supported) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!force && preferences.getInt(_scheduledKey) == minutes) return;
      if (!_initialized) {
        await Workmanager().initialize(backgroundSyncDispatcher);
        _initialized = true;
      }
      await Workmanager().cancelByUniqueName(_uniqueName);
      if (minutes > 0) {
        await Workmanager().registerPeriodicTask(
          _uniqueName,
          _taskName,
          frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }
      await preferences.setInt(_scheduledKey, minutes);
    } catch (error) {
      debugPrint('Arka plan eşitleme planlanamadı: $error');
    }
  }
}
'@

  # ============================================================ 4) APP STORE
  Write-Host "`n[2] AppStore (arka plan / on plan esitleme)" -ForegroundColor Cyan
  Edit-Once $F_STORE "import '../utils/date_helper.dart';" "import '../utils/date_helper.dart';`nimport 'background_sync.dart';" 'background_sync import'
  Edit-Once $F_STORE 'class AppStore extends ChangeNotifier {' 'class AppStore extends ChangeNotifier with WidgetsBindingObserver {' 'WidgetsBindingObserver'
  Edit-Once $F_STORE @'
      unawaited(store._initializeFirestore());
    }
'@ @'
      unawaited(store._initializeFirestore());
    }
    store._attachLifecycle();
'@ 'yasam dongusu baglantisi'
  Edit-Once $F_STORE @'
    await _preferences.setInt(_syncIntervalKey, minutes);
    _restartSyncTimer();
'@ @'
    await _preferences.setInt(_syncIntervalKey, minutes);
    _restartSyncTimer();
    if (_firestore != null) {
      unawaited(BackgroundSync.schedule(minutes, force: true));
    }
'@ 'aralik degisince arka plan gorevi'
  $storeMethods = @'
  // ---------------------------------------------------------------------------
  // ARKA PLAN / ÖN PLAN
  //
  // * Android: WorkManager görevi (background_sync.dart) uygulama kapalıyken de
  //   seçilen aralıkta eşitler.
  // * Uygulama öne gelince: arka planda değişen veriler yeniden okunur ve süre
  //   dolduysa hemen eşitlenir (zamanlayıcı arka planda durmuş olabilir).
  // ---------------------------------------------------------------------------

  static const String _foregroundKey = 'appForegroundAt';

  void _attachLifecycle() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_markForeground(true));
  }

  Future<void> _markForeground(bool value) async {
    if (value) {
      await _preferences.setString(
        _foregroundKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } else {
      await _preferences.remove(_foregroundKey);
    }
  }

  bool get _syncDue {
    final minutes = syncIntervalMinutes;
    if (minutes <= 0) return false;
    final last = lastSuccessfulSync;
    return last == null ||
        DateTime.now().difference(last) >= Duration(minutes: minutes);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_handleResumed());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_markForeground(false));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  bool _differs(String key, List<dynamic> current) =>
      jsonEncode(current.map((item) => item.toJson()).toList()) !=
      (_preferences.getString(key) ?? '[]');

  Future<void> _handleResumed() async {
    await _markForeground(true);
    if (_busyCount == 0) {
      await _preferences.reload();
      final changed =
          _differs('customers', _customers) ||
          _differs('adSpaces', _adSpaces) ||
          _differs('contracts', _contracts);
      if (changed) {
        _customers = _readList('customers', CustomerModel.fromJson);
        _adSpaces = _readList('adSpaces', AdSpaceModel.fromJson);
        _contracts = _readList('contracts', ContractModel.fromJson);
        _publishSyncStatus();
        notifyListeners();
      }
    }
    _restartSyncTimer();
    if (_firestore != null && _syncDue) unawaited(syncNow());
  }

  /// Android arka plan görevi için başsız (arayüzsüz) eşitleme.
  static Future<bool> runBackgroundSync(FirebaseFirestore firestore) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final foregroundAt = DateTime.tryParse(
      preferences.getString(_foregroundKey) ?? '',
    );
    if (foregroundAt != null &&
        DateTime.now().toUtc().difference(foregroundAt.toUtc()) <
            const Duration(hours: 6)) {
      // Uygulama ön planda: kendi zamanlayıcısı eşitliyor, çakışma olmasın.
      return true;
    }
    final store = AppStore._(preferences, firestore);
    try {
      await store.syncNow();
      return store.syncError == null;
    } finally {
      store.dispose();
    }
  }

  void _restartSyncTimer() {
'@
  Edit-Once $F_STORE '  void _restartSyncTimer() {' $storeMethods 'yasam dongusu ve runBackgroundSync metotlari'
  Edit-Once $F_STORE @'
    _syncTimer?.cancel();
    themeMode.dispose();
'@ @'
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    themeMode.dispose();
'@ 'dispose: observer kaldir'

  Write-Host "`n[3] main.dart + ayarlar metni" -ForegroundColor Cyan
  Edit-Once $F_MAIN "import 'core/services/app_store.dart';" "import 'core/services/app_store.dart';`nimport 'core/services/background_sync.dart';" 'main: import'
  Edit-Once $F_MAIN '  runApp(RSTDolapdereApp(store: store));' @'
  if (firestore != null) {
    unawaited(BackgroundSync.schedule(store.syncIntervalMinutes));
  }
  runApp(RSTDolapdereApp(store: store));
'@ 'main: arka plan gorevi kaydi'
  Edit-Once $F_SET 'son eşitlemeden beri değişenler alınır.' 'son eşitlemeden beri değişenler alınır. Android cihazlarda uygulama arka plandayken veya kapalıyken de seçilen aralıkta (en az 15 dk) eşitlenir.' 'ayarlar: aciklama metni'

  # ============================================================ 5) PDF SERVISI
  Write-Host "`n[4] Sozlesme PDF (sade sutunlar + toplam)" -ForegroundColor Cyan
  $pdfService = @'
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../core/utils/date_helper.dart';
import '../../../models/contract_model.dart';

class ContractPdfService {
  /// [contracts] ekranda o an görünen (filtrelenmiş / sıralanmış) listedir.
  static Future<void> exportContracts(
    AppStore store,
    List<ContractModel> contracts, {
    String? filterSummary,
  }) async {
    final bytes = await buildContractsPdf(
      store,
      contracts,
      filterSummary: filterSummary,
    );
    final fileName =
        'rst-sozlesmeleri-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static String _status(ContractModel contract) {
    final days = DateHelper.daysUntil(contract.endDate);
    if (contract.isFinalized) return 'Bitti';
    if (days < 0) return 'Süresi doldu';
    if (!contract.isActive) return 'Pasif';
    if (DateHelper.daysUntil(contract.startDate) > 0) return 'Başlayacak';
    return 'Aktif';
  }

  static String _remaining(ContractModel contract) {
    if (contract.isFinalized) return '-';
    final days = DateHelper.daysUntil(contract.endDate);
    if (days < 0) return '-';
    if (days == 0) return 'Bugün';
    return ContractRemainingTime.format(days);
  }

  static Future<Uint8List> buildContractsPdf(
    AppStore store,
    List<ContractModel> contracts, {
    String? filterSummary,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final document = pw.Document(
      title: 'RST Dolapdere Sözleşme Listesi',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı sözleşmeleri',
    );
    final dateFormat = DateFormat('dd.MM.yyyy');
    final currencyFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final total = contracts.fold<double>(
      0,
      (sum, contract) => sum + contract.monthlyPrice,
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
                    'RST DOLAPDERE  |  SÖZLEŞMELER',
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
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(1.8),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(1.3),
              6: pw.FlexColumnWidth(1.3),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Kiracı',
                  'Bitiş',
                  'Süre',
                  'Kalan süre',
                  'Bedel',
                  'Durum',
                ],
                boldFont,
                header: true,
              ),
              ...contracts.map((contract) {
                final customer = store.customerFor(contract.customerId);
                final space = store.adSpaceFor(contract.adSpaceId);
                final unit = contract.durationUnit == ContractDurationUnit.month
                    ? 'ay'
                    : 'yıl';
                return _row([
                  space?.name ?? 'Reklam alanı',
                  customer?.name ?? 'Müşteri',
                  dateFormat.format(contract.endDate),
                  '${contract.durationCount} $unit',
                  _remaining(contract),
                  currencyFormat.format(contract.monthlyPrice),
                  _status(contract),
                ], font);
              }),
              _row(
                [
                  'TOPLAM (${contracts.length} sözleşme)',
                  '',
                  '',
                  '',
                  '',
                  currencyFormat.format(total),
                  '',
                ],
                boldFont,
                total: true,
              ),
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
    bool total = false,
  }) => pw.TableRow(
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey200)
        : total
        ? const pw.BoxDecoration(color: PdfColors.grey100)
        : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: font,
                fontSize: total ? 9 : 8,
                fontWeight: total ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(),
  );
}
'@
  Replace-Whole $F_PDF 'buildContractsPdf' $pdfService 'contract_pdf_service.dart'

  # ============================================================ 6) BILDIRIM EKRANI
  Write-Host "`n[5] Bildirimler (Incele = ayni ekranda detay, PDF ikonu)" -ForegroundColor Cyan
  $notif = @'
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../models/contract_model.dart';
import '../../../models/customer_model.dart';
import '../../records/management_screens.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    required this.store,
    this.onReviewContract,
  });

  final AppStore store;

  /// Artık kullanılmıyor: "İncele" bildirimler ekranında detay penceresini açar,
  /// sözleşmeler sayfasına yönlendirmez. (Geriye dönük uyumluluk için duruyor.)
  final ValueChanged<String>? onReviewContract;

  Future<void> _openWhatsApp(
    BuildContext context,
    ContractModel contract,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final customer = store.customerFor(contract.customerId);
    var phone = (customer?.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Müşterinin telefon numarası kayıtlı değil.'),
        ),
      );
      return;
    }
    if (phone.startsWith('00')) phone = phone.substring(2);
    if (phone.startsWith('0')) phone = phone.substring(1);
    if (phone.length == 10) phone = '90$phone';
    final space = store.adSpaceFor(contract.adSpaceId);
    final daysRemaining = DateHelper.daysUntil(contract.endDate);
    final remainingText = switch (daysRemaining) {
      0 => 'Sözleşme bugün sona eriyor.',
      > 0 => 'Sözleşmenin bitmesine $daysRemaining gün kalıyor.',
      _ => 'Sözleşme ${daysRemaining.abs()} gün önce sona erdi.',
    };
    final text =
        'RST Dolapdere sözleşme hatırlatması: '
        '${customer?.name ?? 'Kiracı'} kiracısının ${space?.name ?? 'Reklam alanı'} '
        'sözleşmesi ${DateFormat('dd.MM.yyyy').format(contract.endDate)} tarihinde sona eriyor. '
        '$remainingText';
    final uri = Uri.https('wa.me', '/$phone', {'text': text});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('WhatsApp açılamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final contracts =
            store.activeContracts
                .where(
                  (contract) =>
                      DateHelper.daysUntil(contract.endDate) <=
                      store.reminderOffsets.reduce((a, b) => a > b ? a : b),
                )
                .toList()
              ..sort((a, b) => a.endDate.compareTo(b.endDate));
        final horizontalPadding = MediaQuery.sizeOf(context).width < 600
            ? 16.0
            : 24.0;
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
              Text(
                'Bildirimler',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seçilen günlerde sözleşme hatırlatmaları',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (contracts.isEmpty)
                Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Yaklaşan sözleşme bulunmuyor.',
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
                ...contracts.map(
                  (contract) => _ReminderCard(
                    contract: contract,
                    customer: store.customerFor(contract.customerId),
                    spaceName:
                        store.adSpaceFor(contract.adSpaceId)?.name ??
                        'Reklam alanı',
                    showWhatsapp: true,
                    onWhatsapp: () => _openWhatsApp(context, contract),
                    reminderOffsets: store.reminderOffsets,
                    // Sözleşmeler ekranındaki "Detayları görüntüle" ile aynı
                    // pencere; bildirimler ekranından ayrılmadan açılır.
                    onReview: () => showContractDetails(context, store, contract),
                    onOpenPdf: contract.hasPdf
                        ? () => openContractPdfFile(context, contract)
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.contract,
    required this.customer,
    required this.spaceName,
    required this.showWhatsapp,
    required this.onWhatsapp,
    required this.reminderOffsets,
    required this.onReview,
    this.onOpenPdf,
  });

  final ContractModel contract;
  final CustomerModel? customer;
  final String spaceName;
  final bool showWhatsapp;
  final VoidCallback onWhatsapp;
  final List<int> reminderOffsets;
  final VoidCallback onReview;
  final VoidCallback? onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final days = DateHelper.daysUntil(contract.endDate);
    final titleMaxWidth = MediaQuery.sizeOf(context).width < 380
        ? 180.0
        : 220.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_busy_outlined,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: titleMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spaceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${customer?.name ?? 'Müşteri'} • ${DateFormat('dd.MM.yyyy').format(contract.endDate)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  days == 0
                      ? 'Bugün'
                      : days > 0
                      ? '$days gün'
                      : '${days.abs()} gün geçti',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onOpenPdf != null)
                    IconButton(
                      tooltip: 'Sözleşme PDF\'ini aç',
                      onPressed: onOpenPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                  TextButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('İncele'),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final threshold in reminderOffsets)
                  _ReminderChip(
                    label: threshold == 0 ? 'Son gün' : '$threshold gün kala',
                    active: days <= threshold,
                  ),
              ],
            ),
            if (showWhatsapp && (customer?.phone ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onWhatsapp,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Kiracıya WhatsApp gönder'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  const _ReminderChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      active ? Icons.check_circle : Icons.schedule,
      size: 16,
      color: active
          ? AppColors.success
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}
'@
  Replace-Whole $F_NOTIF 'class _ReminderChip' $notif 'notification_screen.dart'

  # ============================================================ 7) MANAGEMENT SCREENS
  Write-Host "`n[6] management_screens.dart (filtre, siralama, secim, detay, form)" -ForegroundColor Cyan
  $M = $F_MGMT

  Edit-Once $M "import '../../core/utils/date_helper.dart';" "import '../../core/utils/date_helper.dart';`nimport '../../core/utils/turkish_text.dart';" 'import: turkish_text'

  $enums = @'
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
  builder: (context) =>
      ContractDetailsDialog(store: store, contract: contract),
);
'@
  Edit-Once $M @'
enum ContractListFilter { all, active, upcoming, expired }

enum AdSpaceListFilter { all, available, occupied }
'@ $enums 'enum ve yardimci fonksiyonlar'

  $fields = @'
  CustomerListFilter _customerFilter = CustomerListFilter.all;
  CustomerSort _customerSort = CustomerSort.nameAsc;
  ContractSort _contractSort = ContractSort.endAsc;
  AdSpaceSort _adSpaceSort = AdSpaceSort.nameAsc;
  EndedContractFilter _endedFilter = EndedContractFilter.all;
  DateTimeRange? _dateRange;
  ContractDateField _dateField = ContractDateField.end;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
'@
  Edit-Once $M '  bool _nearestFirst = true;' $fields 'durum alanlari'

  Edit-Once $M '    _adSpaceFilter = widget.initialAdSpaceFilter;' @'
    _adSpaceFilter = widget.initialAdSpaceFilter;
    if (widget.showEndedContracts) _contractSort = ContractSort.endDesc;
'@ 'biten sozlesmeler varsayilan siralama'

  $records = @'
  List<dynamic> get _records {
    final records = switch (widget.type) {
      RecordType.adSpaces => _adSpaceRecords(),
      RecordType.customers => _customerRecords(),
      RecordType.contracts => _contractRecords(),
    };
    final query = TurkishText.fold(_query.trim());
    if (query.isEmpty) return records;
    return records
        .where((record) => TurkishText.fold(_searchText(record)).contains(query))
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
              EndedContractFilter.expired =>
                !contract.isFinalized && days < 0,
            }
          : switch (_contractFilter) {
              ContractListFilter.all => true,
              ContractListFilter.active =>
                store.activeContracts.any((active) => active.id == contract.id) ||
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
'@
  Edit-Span $M '  List<dynamic> get _records {' @'
  @override
  void dispose() {
    _searchController.dispose();
'@ $records 'filtre + siralama + arama mantigi'

  Edit-Once $M @'
      await ContractPdfService.exportContracts(
        widget.store,
        records.whereType<ContractModel>().toList(),
      );
'@ @'
      await ContractPdfService.exportContracts(
        widget.store,
        records.whereType<ContractModel>().toList(),
        filterSummary: _filterSummary(),
      );
'@ 'PDF: filtre ozeti'

  $methods = @'
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
          _dropdown<ContractDateField>(
            label: 'Tarih alanı',
            value: _dateField,
            items: const [
              (ContractDateField.end, 'Bitiş tarihi'),
              (ContractDateField.start, 'Başlangıç tarihi'),
            ],
            onChanged: (value) => setState(() => _dateField = value),
          ),
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
    final endable = selected.where((contract) => !contract.isFinalized).toList();
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
'@
  Edit-Once $M '  Future<void> _delete(dynamic record) async {' $methods 'filtre/secim/toplu islem metotlari'

  # --- kayit kutusu (tile) ---
  Edit-Once $M @'
      subtitle = [
        record.company,
        record.phone,
        record.email,
      ].where((part) => part.isNotEmpty).join(' • ');
'@ @'
      subtitle = [
        record.address,
        record.phone,
        record.email,
      ].where((part) => part.isNotEmpty).join(' • ');
'@ 'musteri satiri: adres'

  Edit-Once $M @'
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: Icon(icon, color: AppColors.primary),
        ),
'@ @'
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
'@ 'sozlesme satiri: onay kutusu'

  # --- build ---
  Edit-Span $M '              if (contracts && !widget.showEndedContracts) ...[' @'
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
'@ @'
              if (contracts) ..._contractControls(records),
              if (widget.type == RecordType.adSpaces) ..._adSpaceControls(),
              if (widget.type == RecordType.customers) ..._customerControls(),
'@ 'ekran ustu filtre/siralama alanlari'

  Edit-Once $M @'
              const SizedBox(height: 16),
              if (records.isEmpty)
'@ @'
              const SizedBox(height: 16),
              if (records.isNotEmpty) _summaryLine(records),
              if (records.isEmpty)
'@ 'liste ozeti (adet + toplam bedel)'

  # --- sozlesme detay penceresi ---
  Edit-All $M '_ContractDetailsDialog' 'ContractDetailsDialog' 'ContractDetailsDialog herkese acik'

  Edit-Once $M "              Text('Bitiş: `${dateFormat.format(contract.endDate)}')," @'
              Text('Bitiş: ${dateFormat.format(contract.endDate)}'),
              Text('Kalan süre: ${contractRemainingLabel(contract)}'),
'@ 'sozlesme detayi: kalan sure'

  Edit-Once $M @'
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
'@ @'
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
'@ 'sozlesme detayi: PDF butonu'

  # --- musteri detay penceresi ---
  Edit-Once $M @'
              if (customer.company.isNotEmpty)
                Text('Firma: ${customer.company}'),
'@ @'
              if (customer.address.isNotEmpty)
                Text('Adres: ${customer.address}'),
'@ 'musteri detayi: adres'

  $custTile = @'
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
                          onPressed: () => openContractPdfFile(context, contract),
                        ),
                    ],
                  ),
                );
'@
  Edit-Span $M @'
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.location_city_outlined),
'@ @'
              }),
            ],
          ),
        ),
      ),
      actions: [
'@ $custTile 'musteri detayi: kalan sure + sozlesme PDF'

  # --- musteri formu ---
  Edit-Once $M '  late final TextEditingController _company;' @'
  late final TextEditingController _company;
  late final TextEditingController _address;
'@ 'form: adres denetleyicisi'
  Edit-Once $M @'
    _company = TextEditingController(
      text: initial is CustomerModel ? initial.company : '',
    );
'@ @'
    _company = TextEditingController(
      text: initial is CustomerModel
          ? (initial.company.trim().isNotEmpty ? initial.company : initial.name)
          : '',
    );
    _address = TextEditingController(
      text: initial is CustomerModel ? initial.address : '',
    );
'@ 'form: baslangic degerleri'
  Edit-Once $M @'
      _name,
      _company,
'@ @'
      _name,
      _company,
      _address,
'@ 'form: dispose'
  Edit-Once $M @'
            name: _name.text.trim(),
            company: _company.text.trim(),
            phone: _phone.text.trim(),
'@ @'
            name: _company.text.trim(),
            company: _company.text.trim(),
            address: _address.text.trim(),
            phone: _phone.text.trim(),
'@ 'form: kaydetme (ad = firma adi)'
  Edit-Once $M @'
                  _textField('Ad soyad', _name, required: true),
                  _textField('Firma', _company),
'@ @'
                  _textField('Firma adı', _company, required: true),
                  _textField('Adres', _address, maxLines: 2),
'@ 'form: Firma adi ustte, Adres alani'

  Write-Host "`nTum baglanti noktalari dogrulandi." -ForegroundColor Green
}
catch {
  Write-Host "`nHATA: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Hicbir dosya degistirilmedi. Bu mesaji bana gonderin." -ForegroundColor Yellow
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
foreach ($f in 'pubspec.yaml', 'pubspec.lock') {
  $p = Join-Path $root $f
  if (Test-Path $p) { Copy-Item $p $backup -Force }
}
Write-Host "`nYedek alindi: $backup" -ForegroundColor Cyan

# ------------------------------------------------------------------ paket
if (-not $PaketEklemeyiAtla) {
  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "flutter komutu bulunamadi; workmanager eklenemedi. Dosyalar YAZILMADI." -ForegroundColor Red
    exit 1
  }
  Write-Host "workmanager paketi ekleniyor..." -ForegroundColor Cyan
  Push-Location $root
  $ErrorActionPreference = 'Continue'
  try { & flutter pub add workmanager; $pubCode = $LASTEXITCODE } finally { Pop-Location; $ErrorActionPreference = 'Stop' }
  if ($pubCode -ne 0) {
    Copy-Item (Join-Path $backup 'pubspec.yaml') (Join-Path $root 'pubspec.yaml') -Force
    if (Test-Path (Join-Path $backup 'pubspec.lock')) { Copy-Item (Join-Path $backup 'pubspec.lock') (Join-Path $root 'pubspec.lock') -Force }
    Write-Host "flutter pub add basarisiz. pubspec geri alindi, kod dosyalari YAZILMADI." -ForegroundColor Red
    exit 1
  }
}

# ------------------------------------------------------------------ yazma
foreach ($f in @($F_MGMT, $F_NOTIF, $F_PDF, $F_CUST, $F_STORE, $F_MAIN, $F_SET)) {
  Save-File $f
  Write-Host "  yazildi: $f" -ForegroundColor DarkGreen
}
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $root $F_TRTXT), ($turkishText -replace "`r`n", "`n"), $utf8)
[IO.File]::WriteAllText((Join-Path $root $F_BGSYNC), ($bgSync -replace "`r`n", "`n"), $utf8)
Write-Host "  yeni: $F_TRTXT" -ForegroundColor DarkGreen
Write-Host "  yeni: $F_BGSYNC" -ForegroundColor DarkGreen

# ------------------------------------------------------------------ analiz
if (-not $AnalizeAtla -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "`nflutter analyze calistiriliyor..." -ForegroundColor Cyan
  Push-Location $root
  $ErrorActionPreference = 'Continue'
  try { & flutter analyze --no-pub 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -Last 60 } finally { Pop-Location; $ErrorActionPreference = 'Stop' }
}

Write-Host "`nBITTI. Yedek: $backup" -ForegroundColor Green
Write-Host "Geri almak icin: Copy-Item '$backup\lib\*' '$root\lib' -Recurse -Force" -ForegroundColor DarkGray
