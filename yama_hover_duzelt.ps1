<#
  yama_hover_duzelt.ps1
  "_EllipseGradientTransform ... invalid_override" hatasini giderir.
  Matrix4 kullanmayan (Transform.scale) yeni _HoverFill ile degistirir.

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_hover_duzelt.ps1
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

if (-not $t.Contains('_EllipseGradientTransform')) {
  Write-Host '_EllipseGradientTransform bulunamadi; duzeltme gerekmiyor veya hover yamasi uygulanmamis.' -ForegroundColor Yellow
  exit 0
}

$startAnchor = '/// Fare üzerine gelince içi merkezden'
$endAnchor   = 'class ContractDetailsDialog extends StatelessWidget {'
$i = $t.IndexOf($startAnchor, [StringComparison]::Ordinal)
if ($i -lt 0) { Write-Host 'Baslangic noktasi bulunamadi. Dosyaya dokunulmadi.' -ForegroundColor Red; exit 1 }
$j = $t.IndexOf($endAnchor, $i, [StringComparison]::Ordinal)
if ($j -lt 0) { Write-Host 'Bitis noktasi bulunamadi. Dosyaya dokunulmadi.' -ForegroundColor Red; exit 1 }

$newClass = @'
/// Fare üzerine gelince içi merkezden dışa doğru [color] ile dolan alan.
/// (Ana paneldeki özet kartlarıyla aynı efekt; geniş kartlarda kare gradyan
/// kartın boyuna uzatılarak elips olarak yayılır.) [color] null ise etkisizdir.
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
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    if (!width.isFinite ||
                        !height.isFinite ||
                        width <= 0 ||
                        height <= 0) {
                      return const SizedBox.shrink();
                    }
                    // Yüksekliği kenar kabul eden kare gradyan, yatayda
                    // kartın genişliğine uzatılır (daire -> elips).
                    return Center(
                      child: Transform.scale(
                        scaleX: width / height,
                        scaleY: 1,
                        child: SizedBox(
                          width: height,
                          height: height,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.center,
                                radius: t * 0.75,
                                colors: [
                                  color.withValues(alpha: 0.12),
                                  color.withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.98, 1.0],
                              ),
                            ),
                          ),
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
'@
$newClass = $newClass -replace "`r`n", "`n"

$t = $t.Substring(0, $i) + $newClass + "`n`n" + $t.Substring($j)

$backup = "$path.yedek_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $path $backup -Force
$out = if ($crlf) { $t -replace "`n", "`r`n" } else { $t }
[IO.File]::WriteAllText($path, $out, (New-Object Text.UTF8Encoding($bom)))
Write-Host "Duzeltme uygulandi: $rel" -ForegroundColor Green
Write-Host "Yedek: $backup" -ForegroundColor DarkGray
