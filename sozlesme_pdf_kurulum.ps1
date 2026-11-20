<#
.SYNOPSIS
    Sozlesme PDF ozelligini projeye ekler (RST Dolapdere / dere_sozlesme_takip).

.DESCRIPTION
    - Sozlesme ekleme/duzenleme/uzatma formuna "PDF yukle" alani ekler.
    - PDF'i uygulamanin kurulu oldugu klasorde su yapida saklar:
        <uygulama klasoru>\sözleşmeler\2026\Alan - Kiraci - 20.11.2026.pdf
        <uygulama klasoru>\sözleşmeler\2026 - 2027\Alan - Kiraci - 20.11.2026.pdf
      (baslangic ve bitis yili aynıysa tek yil, farkliysa "baslangic - bitis")
    - Sozlesme menusune "Sözleşme PDF'ini görüntüle" ekler. PDF, uygulama
      icinde degil varsayilan PDF uygulamasinda, yoksa varsayilan tarayicida acilir.
    - Yeni paket gerekmez (pubspec.yaml degismez).

    Degisecek dosyalar degistirilmeden once .yedek_sozlesme_pdf_<tarih> klasorune yedeklenir.
    Bir kod parcasi bulunamazsa HICBIR dosya degistirilmez.

.PARAMETER ProjectPath
    Flutter proje klasoru (pubspec.yaml'in oldugu yer). Verilmezse betigin
    bulundugu klasor, o da uygun degilse gecerli klasor kullanilir.

.PARAMETER Analyze
    Islem bitince "flutter analyze" calistirir.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\sozlesme_pdf_kurulum.ps1 -ProjectPath "C:\Users\USER\Desktop\git-desktop\rst-dolapdere"
#>
[CmdletBinding()]
param(
    [string]$ProjectPath,
    [switch]$Analyze
)

$ErrorActionPreference = 'Stop'

# --- Kodlama kontrolu: dosya UTF-8 (BOM'lu) kaydedilmemisse Turkce karakterler bozulur ---
$probe = 'ü'
if ($probe.Length -ne 1 -or [int][char]$probe[0] -ne 252) {
    Write-Host 'HATA: Bu dosya UTF-8 (BOM ile) kaydedilmemis. Dosyayi indirip dogrudan calistirin' -ForegroundColor Red
    Write-Host '      ya da bir editorde "UTF-8 with BOM" olarak kaydedip tekrar deneyin.' -ForegroundColor Red
    exit 1
}

# --- Proje klasorunu bul ---
function Test-ProjectRoot([string]$path) {
    return ($path -and (Test-Path (Join-Path $path 'pubspec.yaml')) -and
            (Test-Path (Join-Path $path 'lib\models\contract_model.dart')))
}
if (-not $ProjectPath) {
    if ($PSScriptRoot -and (Test-ProjectRoot $PSScriptRoot)) { $ProjectPath = $PSScriptRoot }
    else { $ProjectPath = (Get-Location).Path }
}
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-ProjectRoot $ProjectPath)) {
    Write-Host "HATA: '$ProjectPath' bir Flutter proje klasoru gibi gorunmuyor (pubspec.yaml veya lib\models\contract_model.dart yok)." -ForegroundColor Red
    Write-Host '      -ProjectPath ile proje klasorunu belirtin.' -ForegroundColor Red
    exit 1
}
Write-Host "Proje: $ProjectPath" -ForegroundColor Cyan

# --- Yardimcilar ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Source([string]$fullPath) {
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $raw = $raw.Substring(1) }
    $eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{
        Text   = $raw.Replace("`r`n", "`n")
        Eol    = $eol
        HasBom = $hasBom
    }
}

function Write-Source([string]$fullPath, [string]$text, [string]$eol, [bool]$hasBom) {
    $out = $text
    if ($eol -eq "`r`n") { $out = $out.Replace("`n", "`r`n") }
    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($fullPath, $out, $enc)
}

function Get-Count([string]$text, [string]$needle) {
    $n = 0; $i = 0
    while (($i = $text.IndexOf($needle, $i, [System.StringComparison]::Ordinal)) -ge 0) { $n++; $i += $needle.Length }
    return $n
}

$patches = New-Object System.Collections.ArrayList
function Add-Patch([string]$file, [string]$name, [string]$old, [string]$new) {
    [void]$patches.Add([pscustomobject]@{
        File = $file
        Name = $name
        Old  = $old.Replace("`r`n", "`n")
        New  = $new.Replace("`r`n", "`n")
    })
}

# ============================================================================
# 1) YENI DOSYA: lib\features\contracts\services\contract_file_service.dart
# ============================================================================
$serviceRel  = 'lib\features\contracts\services\contract_file_service.dart'
$serviceCode = @'
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';

/// Bir sözleşme PDF'i için hazırlanan dosya işleminin planı.
///
/// Dosya sisteminde kalıcı değişiklik [commit] çağrılana kadar yapılmaz.
/// Sözleşme kaydı başarısız olursa [rollback] ile geçici dosya temizlenir;
/// böylece kayıt ile dosya birbirinden kopmaz.
class ContractPdfFilePlan {
  ContractPdfFilePlan({
    this.relativePath,
    Future<void> Function()? onCommit,
    Future<void> Function()? onRollback,
  }) : _onCommit = onCommit,
       _onRollback = onRollback;

  /// Sözleşme kaydına yazılacak, sözleşmeler klasörüne göre göreli yol.
  final String? relativePath;

  /// [commit] sırasında oluşan hata mesajı (kayıt yine de tamamlanmış olur).
  String? commitWarning;

  final Future<void> Function()? _onCommit;
  final Future<void> Function()? _onRollback;

  Future<void> commit() async {
    try {
      await _onCommit?.call();
    } catch (error) {
      commitWarning = 'PDF dosyası klasöre kaydedilemedi: $error';
    }
  }

  Future<void> rollback() async {
    try {
      await _onRollback?.call();
    } catch (_) {
      // Temizlik hatası kullanıcıyı ilgilendirmez.
    }
  }
}

/// Sözleşme PDF'lerini uygulamanın kurulu olduğu klasörün altındaki
/// `sözleşmeler` klasöründe saklar.
///
/// Yapı:
///   <uygulama klasörü>\sözleşmeler\2026\Alan - Kiracı - 20.11.2026.pdf
///   <uygulama klasörü>\sözleşmeler\2026 - 2027\Alan - Kiracı - 20.11.2026.pdf
class ContractFileService {
  ContractFileService._();

  static const String rootFolderName = 'sözleşmeler';

  static bool get isSupported => !kIsWeb && Platform.isWindows;

  // ---------------------------------------------------------------------------
  // Klasör / dosya adı üretimi
  // ---------------------------------------------------------------------------

  static String folderNameFor(DateTime start, DateTime end) =>
      start.year == end.year
      ? '${start.year}'
      : '${start.year} - ${end.year}';

  static String fileNameFor({
    required String spaceName,
    required String tenantTitle,
    required DateTime startDate,
  }) {
    final space = _limit(_clean(spaceName), 80, 'Alan');
    final tenant = _limit(_clean(tenantTitle), 80, 'Kiracı');
    final date = DateFormat('dd.MM.yyyy').format(startDate);
    return '$space - $tenant - $date.pdf';
  }

  /// Windows'ta dosya adında yasak karakterleri temizler.
  static String _clean(String value) {
    var text = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    text = text.replaceAll(RegExp(r'[. ]+$'), '');
    return text;
  }

  static String _limit(String value, int max, String fallback) {
    if (value.isEmpty) return fallback;
    if (value.length <= max) return value;
    return value.substring(0, max).trim();
  }

  // ---------------------------------------------------------------------------
  // Kök klasör
  // ---------------------------------------------------------------------------

  static String get _primaryRoot {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}$rootFolderName';
  }

  /// Uygulama klasörüne yazılamıyorsa (ör. Program Files) kullanılacak yedek.
  static String get _fallbackRoot {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}RST Dolapdere'
        '${Platform.pathSeparator}$rootFolderName';
  }

  static String? _cachedWritableRoot;

  static Future<String> _writableRoot() async {
    final cached = _cachedWritableRoot;
    if (cached != null) return cached;
    for (final candidate in [_primaryRoot, _fallbackRoot]) {
      try {
        final dir = Directory(candidate);
        await dir.create(recursive: true);
        final probe = File(
          '$candidate${Platform.pathSeparator}.yazma-testi-'
          '${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        _cachedWritableRoot = candidate;
        return candidate;
      } catch (_) {
        continue;
      }
    }
    throw StateError(
      'Sözleşme PDF klasörü oluşturulamadı. Uygulama klasörüne yazma izni '
      'olduğundan emin olun.',
    );
  }

  static String _fullPath(String root, String relativePath) =>
      '$root${Platform.pathSeparator}$relativePath';

  /// Kayıtlı göreli yolu diskteki gerçek dosyaya çevirir (yoksa null).
  static String? _resolveExisting(String? relativePath) {
    final rel = (relativePath ?? '').trim();
    if (rel.isEmpty) return null;
    for (final root in [_primaryRoot, _fallbackRoot]) {
      final full = _fullPath(root, rel);
      if (File(full).existsSync()) return full;
    }
    return null;
  }

  static bool _samePath(String? a, String? b) =>
      a != null && b != null && a.toLowerCase() == b.toLowerCase();

  // ---------------------------------------------------------------------------
  // PDF seçme (Windows dosya seçme penceresi)
  // ---------------------------------------------------------------------------

  /// Windows "Aç" penceresini gösterir. İptal edilirse null döner.
  static Future<String?> pickPdf() async {
    if (!isSupported) return null;
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
$owner.ShowInTaskbar = $false
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Sözleşme PDF dosyasını seçin'
$dialog.Filter = 'PDF dosyaları (*.pdf)|*.pdf'
$dialog.Multiselect = $false
if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Out.Write($dialog.FileName)
}
$owner.Dispose()
''';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64.encode(_utf16le(script)),
    ], stdoutEncoding: utf8);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).replaceAll('\uFEFF', '').trim();
    return path.isEmpty ? null : path;
  }

  static List<int> _utf16le(String value) {
    final bytes = <int>[];
    for (final unit in value.codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // Kaydetme planı
  // ---------------------------------------------------------------------------

  /// Sözleşme kaydedilmeden önce çağrılır.
  ///
  /// * [pickedSourcePath] verilirse seçilen PDF yeni dosya olur.
  /// * [remove] true ise mevcut PDF kayıttan ve diskten kaldırılır.
  /// * İkisi de yoksa ve mevcut PDF varsa, tarih / kiracı / alan değiştiyse
  ///   dosya yeni adına ve klasörüne taşınır.
  static Future<ContractPdfFilePlan> prepare({
    required String spaceName,
    required String tenantTitle,
    required DateTime startDate,
    required DateTime endDate,
    String? existingRelativePath,
    String? pickedSourcePath,
    bool remove = false,
  }) async {
    final existing = (existingRelativePath ?? '').trim();
    final hasExisting = existing.isNotEmpty;
    final picked = (pickedSourcePath ?? '').trim();
    final hasPicked = picked.isNotEmpty;

    if (!isSupported) {
      return ContractPdfFilePlan(relativePath: hasExisting ? existing : null);
    }

    final existingFull = _resolveExisting(existing);

    // PDF kaldırılıyor.
    if (remove && !hasPicked) {
      return ContractPdfFilePlan(
        relativePath: null,
        onCommit: () async {
          if (existingFull != null) {
            await _deleteFile(existingFull);
            await _deleteEmptyParent(existingFull);
          }
        },
      );
    }

    if (!hasPicked && !hasExisting) {
      return ContractPdfFilePlan(relativePath: null);
    }

    // Kayıtlı PDF var ama diskte bulunamıyor: kaydı bozmadan olduğu gibi bırak.
    if (!hasPicked && existingFull == null) {
      return ContractPdfFilePlan(relativePath: existing);
    }

    final root = await _writableRoot();
    final folder = folderNameFor(startDate, endDate);
    final fileName = fileNameFor(
      spaceName: spaceName,
      tenantTitle: tenantTitle,
      startDate: startDate,
    );

    // Aynı adda başka bir sözleşme dosyası varsa ezme: (2), (3)... ekle.
    var relative = '$folder${Platform.pathSeparator}$fileName';
    var finalFull = _fullPath(root, relative);
    var counter = 2;
    while (File(finalFull).existsSync() && !_samePath(finalFull, existingFull)) {
      final base = fileName.substring(0, fileName.length - 4);
      relative = '$folder${Platform.pathSeparator}$base ($counter).pdf';
      finalFull = _fullPath(root, relative);
      counter++;
    }

    final targetDir = Directory(finalFull).parent;
    await targetDir.create(recursive: true);

    // Yeni PDF seçildi: önce geçici dosyaya kopyala, kayıt sonrası yerine koy.
    if (hasPicked) {
      final source = File(picked);
      if (!source.existsSync()) {
        throw StateError('Seçilen PDF dosyası bulunamadı.');
      }
      if (!picked.toLowerCase().endsWith('.pdf') ||
          !await _looksLikePdf(source)) {
        throw StateError('Seçilen dosya geçerli bir PDF değil.');
      }
      final temp = File(
        '${targetDir.path}${Platform.pathSeparator}'
        '.yukleme-${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await source.copy(temp.path);

      return ContractPdfFilePlan(
        relativePath: relative,
        onCommit: () async {
          await _deleteFile(finalFull);
          await temp.rename(finalFull);
          if (existingFull != null && !_samePath(existingFull, finalFull)) {
            await _deleteFile(existingFull);
            await _deleteEmptyParent(existingFull);
          }
        },
        onRollback: () => _deleteFile(temp.path),
      );
    }

    // Yeni PDF yok: mevcut dosya aynı yerdeyse dokunma, değilse taşı.
    if (_samePath(existingFull, finalFull)) {
      return ContractPdfFilePlan(relativePath: relative);
    }
    final oldFull = existingFull!;
    return ContractPdfFilePlan(
      relativePath: relative,
      onCommit: () async {
        final from = File(oldFull);
        try {
          await from.rename(finalFull);
        } on FileSystemException {
          await from.copy(finalFull);
          await from.delete();
        }
        await _deleteEmptyParent(oldFull);
      },
    );
  }

  static Future<bool> _looksLikePdf(File file) async {
    try {
      final raf = await file.open();
      try {
        final head = await raf.read(1024);
        return latin1.decode(head, allowInvalid: true).contains('%PDF');
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  /// Taşıma / silme sonrası boş kalan yıl klasörünü temizler.
  static Future<void> _deleteEmptyParent(String filePath) async {
    try {
      final dir = File(filePath).parent;
      final name = dir.path.split(RegExp(r'[\\/]')).last;
      if (name == rootFolderName) return;
      if (await dir.list().isEmpty) await dir.delete();
    } catch (_) {
      // Boş klasör kalması sorun değil.
    }
  }

  // ---------------------------------------------------------------------------
  // PDF açma
  // ---------------------------------------------------------------------------

  /// Kayıtlı PDF'i varsayılan PDF uygulamasında, yoksa varsayılan tarayıcıda
  /// açar. Uygulama içinde açılmaz. Hata varsa mesaj döner, başarıda null.
  static Future<String?> open(String? relativePath) async {
    if (!isSupported) {
      return 'PDF açma yalnızca Windows sürümünde desteklenir.';
    }
    final full = _resolveExisting(relativePath);
    if (full == null) {
      return 'Sözleşme PDF dosyası bulunamadı: ${relativePath ?? ''}';
    }
    try {
      if (await _hasPdfHandler()) {
        await Process.start('explorer.exe', [
          full,
        ], mode: ProcessStartMode.detached);
        return null;
      }
      if (await _openInDefaultBrowser(full)) return null;
      return 'PDF açmak için varsayılan PDF uygulaması veya tarayıcı '
          'bulunamadı.';
    } catch (error) {
      return 'PDF açılamadı: $error';
    }
  }

  static Future<bool> _hasPdfHandler() async {
    final userChoice = await _regValue(
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice',
      '/v',
      'ProgId',
    );
    if (userChoice != null) return true;
    final classRoot = await _regValue(r'HKCR\.pdf', '/ve');
    return classRoot != null;
  }

  static Future<bool> _openInDefaultBrowser(String filePath) async {
    final fileUri = Uri.file(filePath).toString();
    final progId = await _regValue(
      r'HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice',
      '/v',
      'ProgId',
    );
    String? command;
    if (progId != null) {
      command = await _regValue('HKCR\\$progId\\shell\\open\\command', '/ve');
    }
    command ??= await _regValue(r'HKCR\http\shell\open\command', '/ve');
    if (command == null) return false;

    final text = _expandEnvironment(command.trim());
    String exe;
    if (text.startsWith('"')) {
      final end = text.indexOf('"', 1);
      if (end < 0) return false;
      exe = text.substring(1, end);
    } else {
      exe = text.split(' ').first;
    }
    if (!File(exe).existsSync()) return false;
    await Process.start(exe, [fileUri], mode: ProcessStartMode.detached);
    return true;
  }

  /// `reg query` ile bir kayıt defteri değerini okur; yoksa null döner.
  static Future<String?> _regValue(
    String key,
    String valueSwitch, [
    String? valueName,
  ]) async {
    try {
      final result = await Process.run('reg', [
        'query',
        key,
        valueSwitch,
        ?valueName,
      ]);
      if (result.exitCode != 0) return null;
      final match = RegExp(
        r'REG_(?:EXPAND_)?SZ\s+(.+)$',
        multiLine: true,
      ).firstMatch(result.stdout as String);
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty || value == '(value not set)') {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  static String _expandEnvironment(String value) =>
      value.replaceAllMapped(RegExp(r'%([^%]+)%'), (match) {
        final name = match.group(1)!;
        return Platform.environment[name] ?? match.group(0)!;
      });
}
'@

# ============================================================================
# 2) MEVCUT DOSYALARDAKI DEGISIKLIKLER
# ============================================================================
$old = @'
    this.responsibleUsername,
  });
'@
$new = @'
    this.responsibleUsername,
    this.pdfPath,
  });
'@
Add-Patch 'lib\models\contract_model.dart' 'Model: constructor' $old $new

$old = @'
  final String? responsibleUsername;
'@
$new = @'
  final String? responsibleUsername;

  /// Sözleşme PDF'inin 'sözleşmeler' klasörüne göre göreli yolu.
  final String? pdfPath;

  bool get hasPdf => (pdfPath ?? '').trim().isNotEmpty;
'@
Add-Patch 'lib\models\contract_model.dart' 'Model: alan' $old $new

$old = @'
    responsibleUsername: json['responsibleUsername'] as String?,
'@
$new = @'
    responsibleUsername: json['responsibleUsername'] as String?,
    pdfPath: json['pdfPath'] as String?,
'@
Add-Patch 'lib\models\contract_model.dart' 'Model: fromJson' $old $new

$old = @'
    'responsibleUsername': responsibleUsername,
'@
$new = @'
    'responsibleUsername': responsibleUsername,
    'pdfPath': pdfPath,
'@
Add-Patch 'lib\models\contract_model.dart' 'Model: toJson' $old $new

$old = @'
          contract.responsibleUsername ?? existingContract?.responsibleUsername,
'@
$new = @'
          contract.responsibleUsername ?? existingContract?.responsibleUsername,
      pdfPath: contract.pdfPath,
'@
Add-Patch 'lib\core\services\app_store.dart' 'Store: saveContract' $old $new

$old = @'
      responsibleUsername: source.responsibleUsername,
      history: [
        ...source.history,
        ContractHistoryEntry(
          action: ContractHistoryAction.renewed,
'@
$new = @'
      responsibleUsername: source.responsibleUsername,
      pdfPath: renewed.pdfPath,
      history: [
        ...source.history,
        ContractHistoryEntry(
          action: ContractHistoryAction.renewed,
'@
Add-Patch 'lib\core\services\app_store.dart' 'Store: renewContract' $old $new

$old = @'
    String? responsibleUsername,
  }) {
    return ContractModel(
'@
$new = @'
    String? responsibleUsername,
    String? pdfPath,
  }) {
    return ContractModel(
'@
Add-Patch 'lib\core\services\app_store.dart' 'Store: _copyContract parametre' $old $new

$old = @'
      responsibleUsername: responsibleUsername ?? source.responsibleUsername,
    );
'@
$new = @'
      responsibleUsername: responsibleUsername ?? source.responsibleUsername,
      pdfPath: pdfPath ?? source.pdfPath,
    );
'@
Add-Patch 'lib\core\services\app_store.dart' 'Store: _copyContract gövde' $old $new

$old = @'
import '../contracts/services/contract_pdf_service.dart';
'@
$new = @'
import '../contracts/services/contract_pdf_service.dart';
import '../contracts/services/contract_file_service.dart';
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Ekran: import' $old $new

$old = @'
  Future<void> _showContractDetails(ContractModel contract) => showDialog<void>(
'@
$new = @'
  Future<void> _openContractPdf(ContractModel contract) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ContractFileService.open(contract.pdfPath);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _showContractDetails(ContractModel contract) => showDialog<void>(
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Ekran: PDF aç metodu' $old $new

$old = @'
                      case 'details':
                        _showContractDetails(record);
'@
$new = @'
                      case 'details':
                        _showContractDetails(record);
                      case 'pdf':
                        _openContractPdf(record);
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Ekran: menü seçimi' $old $new

$old = @'
                      if (!ended)
                        const PopupMenuItem(
                          value: 'edit',
'@
$new = @'
                      if (record.hasPdf)
                        const PopupMenuItem(
                          value: 'pdf',
                          child: Text('Sözleşme PDF\'ini görüntüle'),
                        ),
                      if (!ended)
                        const PopupMenuItem(
                          value: 'edit',
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Ekran: menü öğesi' $old $new

$old = @'
  late bool _active;
  String? _error;
'@
$new = @'
  late bool _active;
  String? _error;
  String? _existingPdf;
  String? _newPdfSource;
  bool _removePdf = false;
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Form: durum alanları' $old $new

$old = @'
    final initial = widget.initial;
    _name = TextEditingController(
'@
$new = @'
    final initial = widget.initial;
    _existingPdf = initial is ContractModel ? initial.pdfPath : null;
    _name = TextEditingController(
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Form: initState' $old $new

$old = @'
  double _parsePrice() =>
'@
$new = @'
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
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Form: PDF arayüz metotları' $old $new

$old = @'
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
'@
$new = @'
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
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Form: kaydet' $old $new

$old = @'
                  _textField('Notlar', _notes, maxLines: 3),
                  SwitchListTile(
'@
$new = @'
                  _textField('Notlar', _notes, maxLines: 3),
                  if (ContractFileService.isSupported) _pdfSection(),
                  SwitchListTile(
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Form: PDF bölümü' $old $new

# ============================================================================
# 3) UYGULAMA (once bellekte dene, sonra yedekle ve yaz)
# ============================================================================
# Dosya basina "zaten uygulanmis mi" isareti
$markers = @{
    'lib\models\contract_model.dart'                  = 'pdfPath'
    'lib\core\services\app_store.dart'                = 'pdfPath: contract.pdfPath'
    'lib\features\records\management_screens.dart'    = 'contract_file_service.dart'
}

$files = @{}      # rel -> Read-Source sonucu
$skipped = @()
foreach ($rel in ($patches | ForEach-Object { $_.File } | Select-Object -Unique)) {
    $full = Join-Path $ProjectPath $rel
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "HATA: Dosya bulunamadi: $rel" -ForegroundColor Red
        exit 1
    }
    $src = Read-Source $full
    if ($src.Text.Contains($markers[$rel])) {
        Write-Host "  Atlandi (zaten uygulanmis): $rel" -ForegroundColor Yellow
        $skipped += $rel
        continue
    }
    $files[$rel] = $src
}

$failed = @()
foreach ($p in $patches) {
    if ($skipped -contains $p.File) { continue }
    $src = $files[$p.File]
    $count = Get-Count $src.Text $p.Old
    if ($count -ne 1) {
        $failed += "  - [$($p.File)] $($p.Name): $count eslesme (1 olmaliydi)"
        continue
    }
    $idx = $src.Text.IndexOf($p.Old, [System.StringComparison]::Ordinal)
    $src.Text = $src.Text.Substring(0, $idx) + $p.New + $src.Text.Substring($idx + $p.Old.Length)
}
if ($failed.Count -gt 0) {
    Write-Host 'HATA: Asagidaki kod parcalari projede beklenen sekilde bulunamadi. Hicbir dosya degistirilmedi:' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host 'Dosyalar bu betik hazirlandiktan sonra degismis olabilir; guncel halini gonderirseniz uyarlarim.' -ForegroundColor Red
    exit 1
}

# Yedek
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $ProjectPath ".yedek_sozlesme_pdf_$stamp"
$serviceFull = Join-Path $ProjectPath $serviceRel
foreach ($rel in $files.Keys) {
    $dest = Join-Path $backupRoot $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectPath $rel) -Destination $dest -Force
}
$serviceExisted = Test-Path -LiteralPath $serviceFull
if ($serviceExisted) {
    $dest = Join-Path $backupRoot $serviceRel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath $serviceFull -Destination $dest -Force
}

try {
    # Yeni servis dosyasi (diger dosyalarla ayni satir sonu: CRLF/LF)
    $refEol = "`r`n"
    if ($files.Count -gt 0) { $refEol = ($files.Values | Select-Object -First 1).Eol }
    New-Item -ItemType Directory -Force -Path (Split-Path $serviceFull -Parent) | Out-Null
    Write-Source $serviceFull ($serviceCode.Replace("`r`n", "`n")) $refEol $false
    Write-Host "  Yazildi: $serviceRel" -ForegroundColor Green

    foreach ($rel in $files.Keys) {
        $src = $files[$rel]
        Write-Source (Join-Path $ProjectPath $rel) $src.Text $src.Eol $src.HasBom
        Write-Host "  Guncellendi: $rel" -ForegroundColor Green
    }
}
catch {
    Write-Host "HATA: Yazma sirasinda sorun olustu, yedekten geri aliniyor: $($_.Exception.Message)" -ForegroundColor Red
    foreach ($rel in $files.Keys) {
        Copy-Item -LiteralPath (Join-Path $backupRoot $rel) -Destination (Join-Path $ProjectPath $rel) -Force
    }
    if (-not $serviceExisted -and (Test-Path -LiteralPath $serviceFull)) { Remove-Item -LiteralPath $serviceFull -Force }
    exit 1
}

Write-Host ''
Write-Host "Tamamlandi. Yedek: $backupRoot" -ForegroundColor Cyan

if ($Analyze) {
    Push-Location $ProjectPath
    try { flutter analyze } finally { Pop-Location }
}
else {
    Write-Host 'Sonraki adim:' -ForegroundColor Cyan
    Write-Host '  flutter analyze'
    Write-Host '  flutter run -d windows'
}
