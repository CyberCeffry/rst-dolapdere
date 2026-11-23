<#
  yama_reklam_alani_hover.ps1
  Reklam alanlari listesinde kartin uzerine gelince (hover) ana paneldeki gibi
  kartin ici merkezden disa dogru dolar:
     Kirada  -> "Kirada" yazisinin rengi
     Bos     -> "Bos" yazisinin rengi
     (sure 15 gunden az kalmissa durum yazisi kirmizi oldugu icin dolum de kirmizi)

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_reklam_alani_hover.ps1
#>
param([string]$ProjeYolu = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName } else { Write-Host 'pubspec.yaml bulunamadi.' -ForegroundColor Red; exit 1 }
}

$rel  = 'lib\features\records\management_screens.dart'
$path = Join-Path $root $rel
if (-not (Test-Path $path)) { Write-Host "Dosya yok: $rel" -ForegroundColor Red; exit 1 }

$bytes = [IO.File]::ReadAllBytes($path)
$bom   = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$text  = [Text.Encoding]::UTF8.GetString($bytes)
if ($bom) { $text = $text.Substring(1) }
$crlf = $text.Contains("`r`n")
$t = $text -replace "`r`n", "`n"

if ($t.Contains('_HoverFill')) { Write-Host 'Yama zaten uygulanmis.' -ForegroundColor Yellow; exit 0 }

function Edit-Once([string]$old, [string]$new, [string]$what) {
  $old = $old -replace "`r`n", "`n"; $new = $new -replace "`r`n", "`n"
  $i = $script:t.IndexOf($old, [StringComparison]::Ordinal)
  if ($i -lt 0) { throw "Baglanti noktasi bulunamadi: $what" }
  if ($script:t.IndexOf($old, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "Birden fazla eslesme: $what" }
  $script:t = $script:t.Substring(0, $i) + $new + $script:t.Substring($i + $old.Length)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

try {
  # 1) Kartin icini hover sarmalayiciyla sar (yalnizca reklam alani kayitlari)
  Edit-Once @'
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
'@ @'
    return Card(
      clipBehavior: Clip.antiAlias,
      child: _HoverFill(
        color: record is AdSpaceModel ? statusColor : null,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
'@ 'kart: hover sarmalayici (acilis)'

  Edit-Once @'
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
'@ @'
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
'@ 'kart: hover sarmalayici (kapanis)'

  # 2) Hover dolum widget'i
  Edit-Once 'class ContractDetailsDialog extends StatelessWidget {' @'
/// Fare üzerine gelince içi merkezden dışa doğru [color] ile dolan alan.
/// (Ana paneldeki özet kartlarıyla aynı efekt; geniş kartlarda elips olarak
/// yayılır ki kartın tamamını kaplasın.) [color] null ise hiçbir şey yapmaz.
class _HoverFill extends StatefulWidget {
  const _HoverFill({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  State<_HoverFill> createState() => _HoverFillState();
}

class _HoverFillState extends State<_HoverFill> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    if (color == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _hovering ? 1 : 0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final aspect =
                        constraints.maxHeight > 0 &&
                            constraints.maxWidth > constraints.maxHeight
                        ? constraints.maxWidth / constraints.maxHeight
                        : 1.0;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: t * 1.5,
                          colors: [
                            color.withValues(alpha: 0.12),
                            color.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.98, 1.0],
                          transform: _EllipseGradientTransform(aspect),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            child!,
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Gradyanı yatayda [aspect] kadar genişletir (daire → elips).
class _EllipseGradientTransform extends GradientTransform {
  const _EllipseGradientTransform(this.aspect);

  final double aspect;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final centerX = bounds.center.dx;
    return Matrix4.identity()
      ..setEntry(0, 0, aspect)
      ..setEntry(0, 3, centerX * (1 - aspect));
  }
}

class ContractDetailsDialog extends StatelessWidget {
'@ '_HoverFill widget'
}
catch {
  Write-Host "`nHATA: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Dosyaya dokunulmadi. Bu mesaji bana gonderin.' -ForegroundColor Yellow
  exit 1
}

$backup = "$path.yedek_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $path $backup -Force
$out = if ($crlf) { $t -replace "`n", "`r`n" } else { $t }
[IO.File]::WriteAllText($path, $out, (New-Object Text.UTF8Encoding($bom)))
Write-Host "`nYama uygulandi: $rel" -ForegroundColor Green
Write-Host "Yedek: $backup" -ForegroundColor DarkGray
