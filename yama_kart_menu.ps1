<#
  yama_kart_menu.ps1

   1) Reklam alani kartlari: yukseklik artik icerik kadar (sabit oran yok)
   2) Sabit ust kisim: baslik, filtreler, arama ve "N kayit" satiri yerinde kalir,
      yalnizca liste kismi kayar (Reklam alanlari, Musteriler, Sozlesmeler,
      Biten Sozlesmeler, Rezervasyonlar)
   3) Kayitlarin sagindaki uc nokta menusu: uzay temali, buzlu cam, gradyan cerceve,
      hover'da camgobegi->mor parlama (Sozlesme/Musteri/Alan ve Rezervasyon kartlari)

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_kart_menu.ps1
  Once deneme:  ... -SadeceKontrol
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

$F_MGMT = 'lib\features\records\management_screens.dart'
$F_RES = 'lib\features\reservations\screens\reservation_screen.dart'
$N_MENU = 'lib\shared\widgets\space_menu.dart'

$spaceMenu = @'
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [SpaceMenuButton] menüsündeki bir satır.
class SpaceMenuItem<T> {
  const SpaceMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive; // Silme gibi tehlikeli işlemler gül renginde görünür
}

/// Üç nokta düğmesi + uzay temalı "buzlu cam" açılır menü.
/// Arkayı bulanıklaştırır, gradyan çerçeve ve ışımayla açılır; satırların
/// üzerine gelince camgöbeği → mor parlama olur. Yer yoksa yukarı doğru açılır.
class SpaceMenuButton<T> extends StatefulWidget {
  const SpaceMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.tooltip,
    this.icon = Icons.more_vert,
    this.width = 250,
  });

  final List<SpaceMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final IconData icon;
  final double width;

  @override
  State<SpaceMenuButton<T>> createState() => _SpaceMenuButtonState<T>();
}

class _SpaceMenuButtonState<T> extends State<SpaceMenuButton<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  bool get _isOpen => _entry != null;

  void _open() {
    if (_isOpen) return;
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final estimatedHeight = widget.items.length * 46.0 + 20;
    final spaceBelow = screen.height - (origin.dy + box.size.height) - 12;
    final spaceAbove = origin.dy - 12;
    final openUp = spaceBelow < estimatedHeight && spaceAbove > spaceBelow;
    _entry = OverlayEntry(builder: (context) => _buildOverlay(openUp));
    Overlay.of(context).insert(_entry!);
    setState(() {});
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

  void _select(T value) {
    _close();
    widget.onSelected(value);
  }

  Widget _buildOverlay(bool openUp) {
    const radius = 18.0;
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
          targetAnchor: openUp ? Alignment.topRight : Alignment.bottomRight,
          followerAnchor: openUp ? Alignment.bottomRight : Alignment.topRight,
          offset: Offset(0, openUp ? -6 : 6),
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
            child: Focus(
              autofocus: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.94 + 0.06 * t,
                    alignment: openUp
                        ? Alignment.bottomRight
                        : Alignment.topRight,
                    child: child,
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: SizedBox(
                    width: widget.width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                            blurRadius: 34,
                            offset: const Offset(0, 14),
                          ),
                          BoxShadow(
                            color: const Color(0xFF22D3EE).withValues(alpha: 0.12),
                            blurRadius: 22,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xE61A2150), Color(0xE60E1230)],
                              ),
                              borderRadius: BorderRadius.circular(radius),
                              border: Border.all(
                                color: const Color(0x3DFFFFFF),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final item in widget.items)
                                    _SpaceMenuRow<T>(
                                      item: item,
                                      onTap: () => _select(item.value),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        key: _buttonKey,
        tooltip: widget.tooltip,
        onPressed: _isOpen ? _close : _open,
        icon: Icon(widget.icon),
        color: _isOpen ? const Color(0xFF22D3EE) : null,
      ),
    );
  }
}

class _SpaceMenuRow<T> extends StatefulWidget {
  const _SpaceMenuRow({required this.item, required this.onTap});

  final SpaceMenuItem<T> item;
  final VoidCallback onTap;

  @override
  State<_SpaceMenuRow<T>> createState() => _SpaceMenuRowState<T>();
}

class _SpaceMenuRowState<T> extends State<_SpaceMenuRow<T>> {
  bool _hovering = false;

  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _rose = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accent = item.destructive ? _rose : _cyan;
    final baseColor = item.destructive ? _rose : const Color(0xFFE8ECFF);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: _hovering
                ? LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.24),
                      (item.destructive ? _rose : _violet).withValues(
                        alpha: 0.18,
                      ),
                    ],
                  )
                : null,
            border: Border.all(
              color: _hovering
                  ? accent.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 19,
                  color: _hovering ? accent : baseColor.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: baseColor,
                    fontSize: 14,
                    fontWeight: _hovering ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'@

try {
  foreach ($f in @($F_MGMT, $F_RES)) { Load-File $f }
  if (-not (Test-Path (Join-Path $root 'lib\shared\widgets\space_hover.dart'))) { throw 'space_hover.dart yok. Once yama_uzay_tema.ps1 uygulanmali.' }
  if ($script:buf[$F_MGMT].Contains('SpaceMenuButton')) {
    Write-Host 'Yama zaten uygulanmis gorunuyor (SpaceMenuButton mevcut). Durduruldu.' -ForegroundColor Yellow
    exit 0
  }

  # ============================================================ MANAGEMENT SCREENS
  Write-Host "`n[1] management_screens.dart" -ForegroundColor Cyan
  Edit-Once $F_MGMT "import '../../shared/widgets/space_hover.dart';" "import '../../shared/widgets/space_hover.dart';`nimport '../../shared/widgets/space_menu.dart';" 'import: space_menu'

  # Uc nokta menusu
  Edit-Once $F_MGMT '  Widget _recordTile(dynamic record) {' @'
  List<SpaceMenuItem<String>> _menuItems(dynamic record) {
    if (record is ContractModel) {
      final ended =
          record.isFinalized || DateHelper.daysUntil(record.endDate) < 0;
      return [
        const SpaceMenuItem(
          value: 'details',
          label: 'Detayları görüntüle',
          icon: Icons.visibility_outlined,
        ),
        if (record.hasPdf)
          const SpaceMenuItem(
            value: 'pdf',
            label: 'Sözleşme PDF\'ini görüntüle',
            icon: Icons.picture_as_pdf_outlined,
          ),
        if (!ended)
          const SpaceMenuItem(
            value: 'edit',
            label: 'Düzenle',
            icon: Icons.edit_outlined,
          ),
        if (!record.isFinalized)
          const SpaceMenuItem(
            value: 'end',
            label: 'Bitti olarak işaretle',
            icon: Icons.event_available_outlined,
          ),
        const SpaceMenuItem(
          value: 'renew',
          label: 'Sözleşmeyi uzat',
          icon: Icons.autorenew,
        ),
        const SpaceMenuItem(
          value: 'delete',
          label: 'Sil',
          icon: Icons.delete_outline,
          destructive: true,
        ),
      ];
    }
    return [
      if (record is CustomerModel)
        const SpaceMenuItem(
          value: 'details',
          label: 'Detayları görüntüle',
          icon: Icons.visibility_outlined,
        ),
      const SpaceMenuItem(
        value: 'edit',
        label: 'Düzenle',
        icon: Icons.edit_outlined,
      ),
      const SpaceMenuItem(
        value: 'delete',
        label: 'Sil',
        icon: Icons.delete_outline,
        destructive: true,
      ),
    ];
  }

  Widget _recordTile(dynamic record) {
'@ 'uc nokta menusu: satir listesi'

  Edit-Span $F_MGMT @'
                PopupMenuButton<String>(
                  tooltip: 'Kayıt işlemleri',
'@ @'
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
'@ @'
                SpaceMenuButton<String>(
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
                  items: _menuItems(record),
                ),
'@ 'uc nokta menusu: SpaceMenuButton'

  # Reklam alani kartlari: icerik kadar yukseklik (grid yerine Wrap) - sabit ustten ONCE yapilir
  Edit-Span $F_MGMT '                GridView.builder(' @'
              else
                ...records.map(_recordTile),
'@ @'
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 50.0;
                    final twoColumns = constraints.maxWidth >= 760;
                    final cardWidth = twoColumns
                        ? (constraints.maxWidth - gap) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: gap,
                      runSpacing: 13,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        for (final record in records)
                          SizedBox(width: cardWidth, child: _recordTile(record)),
                      ],
                    );
                  },
                )
'@ 'reklam alani kartlari: icerik kadar yukseklik'

  # Sabit ust kisim + kayan liste
  Edit-Once $F_MGMT @'
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
'@ @'
        return Padding(
          padding: const EdgeInsets.all(24),
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
'@ 'sabit ust kisim (acilis)'
  Edit-Once $F_MGMT @'
              if (records.isNotEmpty) _summaryLine(records),
              if (records.isEmpty)
'@ @'
              if (records.isNotEmpty) _summaryLine(records),
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
'@ 'sabit ust kisim ile liste arasi'
  Edit-Once $F_MGMT @'
              else
                ...records.map(_recordTile),
            ],
          ),
        );
'@ @'
              else
                ...records.map(_recordTile),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
'@ 'sabit ust kisim (kapanis)'

  # ============================================================ REZERVASYON EKRANI
  Write-Host "`n[2] reservation_screen.dart" -ForegroundColor Cyan
  Edit-Once $F_RES "import '../../../shared/widgets/space_hover.dart';" "import '../../../shared/widgets/space_hover.dart';`nimport '../../../shared/widgets/space_menu.dart';" 'import: space_menu'
  Edit-Once $F_RES @'
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
'@ @'
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
'@ 'uc nokta menusu: SpaceMenuButton'
  Edit-Once $F_RES @'
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
'@ @'
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
'@ 'sabit ust kisim (acilis)'
  Edit-Once $F_RES @'
                    '${records.length} rezervasyon',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (records.isEmpty)
'@ @'
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
'@ 'sabit ust kisim ile liste arasi'
  Edit-Once $F_RES @'
              else
                ...records.map(_tile),
            ],
          ),
        );
'@ @'
              else
                ...records.map(_tile),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
'@ 'sabit ust kisim (kapanis)'

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

foreach ($f in @($F_MGMT, $F_RES)) {
  Save-File $f
  Write-Host "  yazildi: $f" -ForegroundColor DarkGreen
}
$path = Join-Path $root $N_MENU
New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
[IO.File]::WriteAllText($path, ($spaceMenu -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "  yeni: $N_MENU" -ForegroundColor DarkGreen

if (-not $AnalizeAtla -and (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "`nflutter analyze calistiriliyor..." -ForegroundColor Cyan
  Push-Location $root
  $ErrorActionPreference = 'Continue'
  try { & flutter analyze --no-pub 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -Last 60 } finally { Pop-Location; $ErrorActionPreference = 'Stop' }
}

Write-Host "`nBITTI. Yedek: $backup" -ForegroundColor Green
Write-Host "Geri almak icin: Copy-Item '$backup\lib\*' '$root\lib' -Recurse -Force" -ForegroundColor DarkGray
