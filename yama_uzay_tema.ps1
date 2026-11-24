<#
  yama_uzay_tema.ps1

   1) Aramada sonuc yoksa "+ Yeni musteri ekle" / "+ Yeni alan ekle" dugmesi
   2) Bos ama rezerve olan reklam alani artik "Rezerve" gorunur (liste, filtre, PDF, panel sayaci)
   3) Koyu uzay temasi: gece gokyuzu, nebula isimalari, yildizlar, buzlu cam kartlar
   4) Hover: reklam alani kartlari AYNEN kalir; diger kartlarda buzlu cam + imleci takip eden
      isik huzmesi + parlayan cerceve (musteri, sozlesme, rezervasyon, bildirim)
   5) Rezervasyonlar: toplu secim, "Sozlesme baslat" (alan bossa sozlesme formu acilir)
   6) Rezervasyon ve reklam alani PDF'lerine sona "Aciklama" (not) sutunu

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_uzay_tema.ps1
  Once deneme:  ... -SadeceKontrol
  Ek: -RenkleriGuncelle  (AppColors primary/success/warning/danger degerlerini koyu zemine gore degistirir; varsayilan: dokunmaz)
  On kosul: yama_uygula.ps1 ve yama_rezervasyon.ps1 uygulanmis olmali.
#>
param(
  [string]$ProjeYolu = (Get-Location).Path,
  [switch]$SadeceKontrol,
  [switch]$AnalizeAtla,
  [switch]$RenkleriGuncelle
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------ yardimcilar
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

# ------------------------------------------------------------------ proje koku
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName } else { Write-Host 'pubspec.yaml bulunamadi.' -ForegroundColor Red; exit 1 }
}
$script:root = $root
Write-Host "Proje: $root" -ForegroundColor Cyan

$F_MAIN = 'lib\main.dart'
$F_MGMT = 'lib\features\records\management_screens.dart'
$F_ADPDF = 'lib\features\records\services\ad_space_pdf_service.dart'
$F_RESPDF = 'lib\features\reservations\services\reservation_pdf_service.dart'
$F_RESSCR = 'lib\features\reservations\screens\reservation_screen.dart'
$F_PICKER = 'lib\shared\widgets\searchable_picker.dart'
$F_NOTIF = 'lib\features\notifications\screens\notification_screen.dart'
$F_DASH = 'lib\features\dashboard\screens\dashboard_screen.dart'
$F_COLORS = 'lib\core\theme\app_colors.dart'
$N_THEME = 'lib\core\theme\space_theme.dart'
$N_HOVER = 'lib\shared\widgets\space_hover.dart'

$spaceTheme = @'
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Uzay temalı, koyu ve "buzlu cam" görünümlü uygulama teması.
class SpaceColors {
  static const Color deep = Color(0xFF060918);
  static const Color night = Color(0xFF0B1030);
  static const Color nebula = Color(0xFF150C33);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color pink = Color(0xFFEC4899);
  static const Color text = Color(0xFFE8ECFF);
  static const Color textMuted = Color(0xFFA7B0D6);
}

class SpaceTheme {
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: SpaceColors.violet,
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF8AA2FF),
          onPrimary: const Color(0xFF0B1030),
          secondary: SpaceColors.cyan,
          tertiary: SpaceColors.pink,
          error: const Color(0xFFFB7185),
          surface: const Color(0xFF10152B),
          onSurface: SpaceColors.text,
          onSurfaceVariant: SpaceColors.textMuted,
          outline: const Color(0x4DFFFFFF),
          outlineVariant: const Color(0x24FFFFFF),
          surfaceContainerHighest: const Color(0x26FFFFFF),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: const Color(0xFF141A38),
    );

    const radius14 = BorderRadius.all(Radius.circular(14));
    final glassBorder = OutlineInputBorder(
      borderRadius: radius14,
      borderSide: const BorderSide(color: Color(0x2EFFFFFF)),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: SpaceColors.text,
        displayColor: SpaceColors.text,
      ),
      cardTheme: CardThemeData(
        color: const Color(0x14FFFFFF),
        surfaceTintColor: Colors.transparent,
        shadowColor: SpaceColors.violet.withValues(alpha: 0.35),
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x24FFFFFF)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xF2121733),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        border: glassBorder,
        enabledBorder: glassBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: SpaceColors.cyan, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: Color(0xFFFB7185)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: const BorderSide(color: Color(0xFFFB7185), width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: SpaceColors.textMuted),
        hintStyle: const TextStyle(color: SpaceColors.textMuted),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xF2141A38),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1B2245),
        contentTextStyle: const TextStyle(color: SpaceColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x2EFFFFFF)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0x1FFFFFFF)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6D5BFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SpaceColors.text,
          side: const BorderSide(color: Color(0x3DFFFFFF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF8AA2FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: SpaceColors.textMuted,
        textColor: SpaceColors.text,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xCC0B1030),
        indicatorColor: const Color(0x338AA2FF),
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2245),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        textStyle: const TextStyle(color: SpaceColors.text, fontSize: 12),
      ),
    );
  }
}

/// Tüm uygulamanın arkasındaki uzay zemini: gece gökyüzü, nebula ışımaları, yıldızlar.
class SpaceBackground extends StatelessWidget {
  const SpaceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: _SpaceBackdrop()),
        child,
      ],
    );
  }
}

class _SpaceBackdrop extends StatelessWidget {
  const _SpaceBackdrop();

  Widget _glow(Alignment alignment, Color color, double radius, double alpha) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: alignment,
          radius: radius,
          colors: [color.withValues(alpha: alpha), Colors.transparent],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SpaceColors.deep, SpaceColors.night, SpaceColors.nebula],
            ),
          ),
        ),
        _glow(const Alignment(-0.95, -0.9), SpaceColors.violet, 0.9, 0.30),
        _glow(const Alignment(1.0, 0.85), SpaceColors.cyan, 0.8, 0.18),
        _glow(const Alignment(0.7, -0.5), SpaceColors.pink, 0.6, 0.10),
        const CustomPaint(painter: _StarPainter()),
      ],
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 170; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final r = 0.4 + random.nextDouble() * 1.0;
      paint
        ..maskFilter = null
        ..color = Colors.white.withValues(
          alpha: 0.18 + random.nextDouble() * 0.55,
        );
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
    for (var i = 0; i < 14; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final tint = i.isEven ? SpaceColors.cyan : Colors.white;
      paint
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..color = tint.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(dx, dy), 1.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
'@

$spaceHover = @'
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Kartların içine konan "buzlu cam" + fütüristik hover efekti:
///  * arkadaki görüntüyü bulanıklaştırır (buzlu cam),
///  * fare üstüne gelince imleci takip eden ışık hüzmesi (spotlight),
///  * kenarlarda camgöbeği → mor → pembe parlayan çerçeve.
/// Reklam alanı kartlarındaki "durum rengiyle dolma" efektine dokunmaz.
class SpaceHover extends StatefulWidget {
  const SpaceHover({
    super.key,
    required this.child,
    this.radius = 20,
    this.blur = 10,
  });

  final Widget child;
  final double radius;
  final double blur;

  @override
  State<SpaceHover> createState() => _SpaceHoverState();
}

class _SpaceHoverState extends State<SpaceHover> {
  bool _hovering = false;
  Offset _position = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: MouseRegion(
          onEnter: (event) => setState(() {
            _hovering = true;
            _position = event.localPosition;
          }),
          onHover: (event) => setState(() => _position = event.localPosition),
          onExit: (_) => setState(() => _hovering = false),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _hovering ? 1 : 0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SpaceHoverPainter(
                        progress: t,
                        position: _position,
                        radius: widget.radius,
                      ),
                    ),
                  ),
                ),
                child!,
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _SpaceHoverPainter extends CustomPainter {
  const _SpaceHoverPainter({
    required this.progress,
    required this.position,
    required this.radius,
  });

  final double progress;
  final Offset position;
  final double radius;

  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _pink = Color(0xFFEC4899);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // İmleci takip eden ışık hüzmesi
    final center = Offset(
      position.dx.clamp(0.0, size.width),
      position.dy.clamp(0.0, size.height),
    );
    final spot = ui.Gradient.radial(
      center,
      260,
      [
        _cyan.withValues(alpha: 0.18 * progress),
        _violet.withValues(alpha: 0.08 * progress),
        Colors.transparent,
      ],
      const [0.0, 0.5, 1.0],
    );
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, Paint()..shader = spot);
    canvas.restore();

    // Parlayan çerçeve
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          _cyan.withValues(alpha: 0.8 * progress),
          _violet.withValues(alpha: 0.8 * progress),
          _pink.withValues(alpha: 0.6 * progress),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRRect(rrect.deflate(0.7), border);
  }

  @override
  bool shouldRepaint(covariant _SpaceHoverPainter old) =>
      old.progress != progress ||
      old.position != position ||
      old.radius != radius;
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
    this.createLabel,
    this.onCreate,
  });

  final String label;
  final List<PickerItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? errorText;
  final String searchHint;
  final String emptyText;

  /// Sonuç bulunamayınca "+ Yeni ..." düğmesinin yazısı (onCreate ile birlikte).
  final String? createLabel;

  /// Yeni kayıt oluşturur ve seçilecek değeri döndürür (vazgeçilirse null).
  final Future<T?> Function()? onCreate;

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

  Future<void> _create() async {
    final onCreate = widget.onCreate;
    if (onCreate == null) return;
    _close();
    final created = await onCreate();
    if (created != null && mounted) widget.onChanged(created);
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
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.emptyText,
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      if (widget.onCreate != null) ...[
                                        const SizedBox(height: 10),
                                        FilledButton.tonalIcon(
                                          onPressed: _create,
                                          icon: const Icon(Icons.add),
                                          label: Text(
                                            widget.createLabel ?? 'Yeni ekle',
                                          ),
                                        ),
                                      ],
                                    ],
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
import '../../../shared/widgets/space_hover.dart';
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
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _openForm(reservation);
                if (value == 'delete') _delete(reservation);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                PopupMenuItem(value: 'delete', child: Text('Sil')),
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

$optionalFiles = @($F_NOTIF, $F_DASH, $F_COLORS)

function Set-ColorConst([string]$name, [string]$hex) {
  $re = "(static\s+const\s+Color\s+$name\s*=\s*)Color\(\s*0x[0-9A-Fa-f]{8}\s*\)"
  $t = $script:buf[$F_COLORS]
  if ([regex]::IsMatch($t, $re)) {
    $script:buf[$F_COLORS] = [regex]::Replace($t, $re, ('${1}Color(' + $hex + ')'))
    Write-Host "  + AppColors.$name = $hex" -ForegroundColor DarkGreen
  }
  else {
    Write-Host "  ! AppColors.$name bulunamadi (atlandi)" -ForegroundColor Yellow
  }
}

try {
  foreach ($f in @($F_MAIN, $F_MGMT, $F_ADPDF, $F_RESPDF, $F_RESSCR, $F_PICKER)) { Load-File $f }
  foreach ($f in $optionalFiles) {
    try { Load-File $f } catch { Write-Host "  ! atlanacak dosya (yok): $f" -ForegroundColor Yellow }
  }
  if ($script:buf[$F_MAIN].Contains('SpaceTheme')) {
    Write-Host 'Yama zaten uygulanmis gorunuyor (SpaceTheme mevcut). Durduruldu.' -ForegroundColor Yellow
    exit 0
  }
  if (-not $script:buf[$F_RESSCR].Contains('_ReservationFormDialog')) { throw 'Once yama_rezervasyon.ps1 uygulanmali (rezervasyon ekrani bulunamadi).' }

  # ============================================================ 1) TEMA
  Write-Host "`n[1] Uzay temasi" -ForegroundColor Cyan
  Edit-Once $F_MAIN "import 'core/theme/app_theme.dart';" "import 'core/theme/app_theme.dart';`nimport 'core/theme/space_theme.dart';" 'main: import'
  if ($script:buf[$F_MAIN] -match '(?m)^[ \t]*builder:[ \t]*\(context, child\)') {
    Fail $F_MAIN 'main.dart: MaterialApp icinde zaten bir builder: (context, child) var'
  }
  else {
    Replace-KeyLine $F_MAIN 'theme' ("theme: SpaceTheme.dark,`n" + '        builder: (context, child) =>' + "`n" + '            SpaceBackground(child: child ?? const SizedBox.shrink()),') $true
    Replace-KeyLine $F_MAIN 'darkTheme' 'darkTheme: SpaceTheme.dark,' $false
    Replace-KeyLine $F_MAIN 'themeMode' 'themeMode: ThemeMode.dark,' $false
  }

  if ($RenkleriGuncelle -and $script:buf.ContainsKey($F_COLORS)) {
    Write-Host "  AppColors (koyu zeminde okunur renkler)" -ForegroundColor Cyan
    Set-ColorConst 'primary' '0xFF8AA2FF'
    Set-ColorConst 'success' '0xFF34D399'
    Set-ColorConst 'warning' '0xFFFBBF24'
    Set-ColorConst 'danger'  '0xFFFB7185'
  }

  # ============================================================ 2) ARAMALI SECICI + YENI KAYIT
  Write-Host "`n[2] Aramada sonuc yoksa '+ Yeni ...' dugmesi" -ForegroundColor Cyan
  Replace-Whole $F_PICKER 'class SearchablePicker' $searchablePicker 'searchable_picker.dart'

  Edit-Once $F_MGMT "import '../../shared/widgets/searchable_picker.dart';" "import '../../shared/widgets/searchable_picker.dart';`nimport '../../shared/widgets/space_hover.dart';" 'management: import space_hover'
  Edit-Once $F_MGMT 'onChanged: (value) => setState(() => _customerId = value),' @'
createLabel: '+ Yeni müşteri ekle',
                    onCreate: () =>
                        showCreateCustomerDialog(context, widget.store),
                    onChanged: (value) => setState(() => _customerId = value),
'@ 'sozlesme formu: + Yeni musteri'
  Edit-Once $F_MGMT 'onChanged: (value) => setState(() => _adSpaceId = value),' @'
createLabel: '+ Yeni alan ekle',
                    onCreate: () =>
                        showCreateAdSpaceDialog(context, widget.store),
                    onChanged: (value) => setState(() => _adSpaceId = value),
'@ 'sozlesme formu: + Yeni alan'

  Edit-Once $F_MGMT 'class _RecordFormDialog extends StatefulWidget {' @'
/// Yeni müşteri formunu açar; kaydedilirse yeni müşterinin kimliğini döndürür.
Future<String?> showCreateCustomerDialog(
  BuildContext context,
  AppStore store,
) async {
  final before = store.customers.map((item) => item.id).toSet();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _RecordFormDialog(store: store, type: RecordType.customers),
  );
  if (saved != true) return null;
  for (final item in store.customers) {
    if (!before.contains(item.id)) return item.id;
  }
  return null;
}

/// Yeni reklam alanı formunu açar; kaydedilirse yeni alanın kimliğini döndürür.
Future<String?> showCreateAdSpaceDialog(
  BuildContext context,
  AppStore store,
) async {
  final before = store.adSpaces.map((item) => item.id).toSet();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _RecordFormDialog(store: store, type: RecordType.adSpaces),
  );
  if (saved != true) return null;
  for (final item in store.adSpaces) {
    if (!before.contains(item.id)) return item.id;
  }
  return null;
}

/// Rezervasyondan sözleşme başlatmak için sözleşme formunu müşteri ve alan
/// seçili olarak açar. Kaydedilirse true döner.
Future<bool?> showStartContractDialog(
  BuildContext context,
  AppStore store, {
  required String customerId,
  required String adSpaceId,
}) => showDialog<bool>(
  context: context,
  builder: (context) => _RecordFormDialog(
    store: store,
    type: RecordType.contracts,
    prefillCustomerId: customerId,
    prefillAdSpaceId: adSpaceId,
  ),
);

class _RecordFormDialog extends StatefulWidget {
'@ 'yeni kayit / sozlesme baslat yardimcilari'
  Edit-Once $F_MGMT @'
    this.isRenewal = false,
  });
'@ @'
    this.isRenewal = false,
    this.prefillCustomerId,
    this.prefillAdSpaceId,
  });
'@ 'form: onceden secili musteri/alan (yapici)'
  Edit-Once $F_MGMT '  final bool isRenewal;' @'
  final bool isRenewal;
  final String? prefillCustomerId;
  final String? prefillAdSpaceId;
'@ 'form: onceden secili musteri/alan (alanlar)'
  Edit-Once $F_MGMT '        : widget.store.customers.firstOrNull?.id;' '        : (widget.prefillCustomerId ?? widget.store.customers.firstOrNull?.id);' 'form: baslangic musteri'
  Edit-Once $F_MGMT '        : widget.store.adSpaces.firstOrNull?.id;' '        : (widget.prefillAdSpaceId ?? widget.store.adSpaces.firstOrNull?.id);' 'form: baslangic alan'

  # ============================================================ 3) REZERVE GORUNUMU
  Write-Host "`n[3] Bos + rezerve = Rezerve" -ForegroundColor Cyan
  Edit-Once $F_MGMT 'enum AdSpaceListFilter { all, available, occupied, expiring }' 'enum AdSpaceListFilter { all, available, reserved, occupied, expiring }' 'filtre enumu: reserved'
  Edit-Once $F_MGMT '        AdSpaceListFilter.available => contract == null,' @'
        AdSpaceListFilter.available =>
          contract == null && store.reservationForAdSpace(space.id) == null,
        AdSpaceListFilter.reserved =>
          contract == null && store.reservationForAdSpace(space.id) != null,
'@ 'filtre: bos / rezerve ayrimi'
  Edit-Once $F_MGMT "(AdSpaceListFilter.available, 'Boş')," @'
(AdSpaceListFilter.available, 'Boş'),
            (AdSpaceListFilter.reserved, 'Rezerve'),
'@ 'filtre menusu: Rezerve'
  Edit-Once $F_MGMT @'
      status = contract == null ? 'Boş' : 'Kirada';
      statusColor = contract == null ? AppColors.info : AppColors.contract;
'@ @'
      final reservedOnly =
          contract == null &&
          widget.store.reservationForAdSpace(record.id) != null;
      status = contract != null ? 'Kirada' : (reservedOnly ? 'Rezerve' : 'Boş');
      statusColor = contract != null
          ? AppColors.contract
          : (reservedOnly ? AppColors.warning : AppColors.info);
'@ 'durum yazisi ve rengi'

  Edit-Once $F_ADPDF "import '../../../models/ad_space_model.dart';" "import '../../../models/ad_space_model.dart';`nimport '../../../models/contract_model.dart';" 'alan PDF: import'
  Edit-Once $F_ADPDF "isEmpty ? 'Boş' : 'Kirada'," @'
isEmpty
                        ? (store.reservedByNameFor(space.id) != null
                              ? 'Rezerve'
                              : 'Boş')
                        : 'Kirada',
'@ 'alan PDF: durum Rezerve'

  if ($script:buf.ContainsKey($F_DASH)) {
    Edit-Optional $F_DASH "'`${store.adSpaces.where((space) => space.isAvailable).length}'," @'
'${store.adSpaces.where((space) => space.isAvailable && store.reservationForAdSpace(space.id) == null).length}',
'@ 'panel: Bos alan sayaci (rezerveler haric)'
  }

  # ============================================================ 4) HOVER (ad space HARIC her yer)
  Write-Host "`n[4] Hover: buzlu cam + isik huzmesi" -ForegroundColor Cyan
  Edit-Once $F_MGMT '    if (color == null) return widget.child;' '    if (color == null) return SpaceHover(child: widget.child);' 'musteri/sozlesme kartlari: uzay hover (reklam alani ayni kaldi)'

  if ($script:buf.ContainsKey($F_NOTIF)) {
    $saved = $script:buf[$F_NOTIF]
    $script:collect = $false
    try {
      Edit-Once $F_NOTIF "import '../../records/management_screens.dart';" "import '../../../shared/widgets/space_hover.dart';`nimport '../../records/management_screens.dart';" 'bildirim: import'
      Edit-Once $F_NOTIF @'
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
'@ @'
    return Card(
      child: SpaceHover(
        child: Padding(
        padding: const EdgeInsets.all(16),
'@ 'bildirim karti: uzay hover (acilis)'
      Edit-Once $F_NOTIF @'
          ],
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
'@ @'
          ],
        ),
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
'@ 'bildirim karti: uzay hover (kapanis)'
    }
    catch {
      $script:buf[$F_NOTIF] = $saved
      Write-Host '  ! bildirim karti hover atlandi (dosya beklenenden farkli)' -ForegroundColor Yellow
    }
    finally { $script:collect = $true }
  }

  if ($script:buf.ContainsKey($F_DASH)) {
    $saved = $script:buf[$F_DASH]
    $script:collect = $false
    try {
      Edit-Once $F_DASH "import 'package:flutter/material.dart';" "import 'dart:ui' as ui;`n`nimport 'package:flutter/material.dart';" 'panel: dart:ui'
      Edit-Once $F_DASH @'
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
'@ @'
    return Card(
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: InkWell(
        onTap: widget.onTap,
'@ 'panel ozet kartlari: buzlu cam (acilis)'
      Edit-Once $F_DASH @'
          child: _buildContent(context),
        ),
      ),
    );
'@ @'
          child: _buildContent(context),
        ),
        ),
      ),
    );
'@ 'panel ozet kartlari: buzlu cam (kapanis)'
    }
    catch {
      $script:buf[$F_DASH] = $saved
      Write-Host '  ! panel kartlari buzlu cam atlandi (dosya beklenenden farkli)' -ForegroundColor Yellow
    }
    finally { $script:collect = $true }
  }

  # ============================================================ 5) REZERVASYON EKRANI
  Write-Host "`n[5] Rezervasyon: toplu secim + Sozlesme baslat" -ForegroundColor Cyan
  Replace-Whole $F_RESSCR '_ReservationFormDialog' $reservationScreen 'reservation_screen.dart'

  # ============================================================ 6) PDF ACIKLAMA SUTUNU
  Write-Host "`n[6] PDF: sona 'Aciklama' sutunu" -ForegroundColor Cyan
  Edit-Once $F_RESPDF @'
                  'Verilen tutar',
                ],
'@ @'
                  'Verilen tutar',
                  'Açıklama',
                ],
'@ 'rezervasyon PDF: baslik'
  Edit-Once $F_RESPDF @'
                        : currencyFormat.format(contract.monthlyPrice),
                  ],
                  font,
'@ @'
                        : currencyFormat.format(contract.monthlyPrice),
                    reservation.notes.trim().isEmpty
                        ? '-'
                        : reservation.notes.trim(),
                  ],
                  font,
'@ 'rezervasyon PDF: not'
  Edit-Once $F_RESPDF @'
              4: pw.FlexColumnWidth(1.5),
            },
'@ @'
              4: pw.FlexColumnWidth(1.5),
              5: pw.FlexColumnWidth(2.4),
            },
'@ 'rezervasyon PDF: sutun genisligi'

  Edit-Once $F_ADPDF "'Rezerve'," @'
'Rezerve',
                  'Açıklama',
'@ 'alan PDF: Aciklama basligi'
  Edit-Once $F_ADPDF "store.reservedByNameFor(space.id) ?? '-'," @'
store.reservedByNameFor(space.id) ?? '-',
                    _notesFor(store, space, contract),
'@ 'alan PDF: not hucresi'
  Edit-Once $F_ADPDF 'columnWidths: const {' @'
columnWidths: const {
              6: pw.FlexColumnWidth(2.4),
'@ 'alan PDF: sutun genisligi'
  Edit-Once $F_ADPDF '  static pw.TableRow _row(' @'
  /// Duruma özel not: kirada ise sözleşme notu, rezerve ise rezervasyon notu;
  /// ikisi de yoksa reklam alanı açıklaması.
  static String _notesFor(
    AppStore store,
    AdSpaceModel space,
    ContractModel? contract,
  ) {
    final parts = <String>[];
    final contractNote = contract?.notes.trim() ?? '';
    if (contractNote.isNotEmpty) parts.add(contractNote);
    final reservationNote =
        store.reservationForAdSpace(space.id)?.notes.trim() ?? '';
    if (reservationNote.isNotEmpty) {
      parts.add(
        contract == null ? reservationNote : 'Rezervasyon: $reservationNote',
      );
    }
    if (parts.isEmpty) {
      final description = space.description.trim();
      return description.isEmpty ? '-' : description;
    }
    return parts.join('\n');
  }

  static pw.TableRow _row(
'@ 'alan PDF: not yardimcisi'

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

# ------------------------------------------------------------------ yazma
foreach ($f in $script:buf.Keys) {
  Save-File $f
  Write-Host "  yazildi: $f" -ForegroundColor DarkGreen
}
$utf8 = New-Object Text.UTF8Encoding($false)
$newFiles = [ordered]@{}
$newFiles[$N_THEME] = $spaceTheme
$newFiles[$N_HOVER] = $spaceHover
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
