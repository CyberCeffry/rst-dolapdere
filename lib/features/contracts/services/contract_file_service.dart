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
///   [uygulama klasörü]\sözleşmeler\2026\Alan - Kiracı - 20.11.2026.pdf
///   [uygulama klasörü]\sözleşmeler\2026 - 2027\Alan - Kiracı - 20.11.2026.pdf
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