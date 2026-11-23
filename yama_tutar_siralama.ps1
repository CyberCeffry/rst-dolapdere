<#
  yama_tutar_siralama.ps1
  Reklam alanlari ekraninda "Tutar" siralamasi artik kiracinin aktif sozlesme
  tutarina gore calisir (bos alanlar her iki yonde sona gider). Kiracili
  alanlarda satira "Tutar: ..." satiri da eklenir.

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_tutar_siralama.ps1
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

if ($t.Contains('priceOrder(')) { Write-Host 'Yama zaten uygulanmis.' -ForegroundColor Yellow; exit 0 }

function Edit-Once([string]$old, [string]$new, [string]$what) {
  $old = $old -replace "`r`n", "`n"; $new = $new -replace "`r`n", "`n"
  $i = $script:t.IndexOf($old, [StringComparison]::Ordinal)
  if ($i -lt 0) { throw "Baglanti noktasi bulunamadi: $what" }
  if ($script:t.IndexOf($old, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "Birden fazla eslesme: $what" }
  $script:t = $script:t.Substring(0, $i) + $new + $script:t.Substring($i + $old.Length)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

try {
  # 1) Siralama mantigi
  Edit-Once @'
    list.sort((a, b) {
      final result = switch (_adSpaceSort) {
'@ @'
    // Tutar: kiracının aktif sözleşme tutarı. Kiracısız (boş) alanlar
    // hem artan hem azalan sıralamada listenin sonuna gider.
    double? tutar(AdSpaceModel space) =>
        store.activeContractForAdSpace(space.id)?.monthlyPrice;
    int priceOrder(
      AdSpaceModel a,
      AdSpaceModel b, {
      required bool descending,
    }) {
      final x = tutar(a);
      final y = tutar(b);
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return descending ? y.compareTo(x) : x.compareTo(y);
    }

    list.sort((a, b) {
      final result = switch (_adSpaceSort) {
'@ 'tutar siralama yardimcisi'

  Edit-Once @'
        AdSpaceSort.priceDesc => b.monthlyPrice.compareTo(a.monthlyPrice),
        AdSpaceSort.priceAsc => a.monthlyPrice.compareTo(b.monthlyPrice),
'@ @'
        AdSpaceSort.priceDesc => priceOrder(a, b, descending: true),
        AdSpaceSort.priceAsc => priceOrder(a, b, descending: false),
'@ 'tutar siralama (sozlesme tutari)'

  # 2) Etiketler
  Edit-Once "(AdSpaceSort.priceDesc, 'Kira: yüksekten düşüğe')," "(AdSpaceSort.priceDesc, 'Tutar: yüksekten düşüğe')," 'etiket: tutar azalan'
  Edit-Once "(AdSpaceSort.priceAsc, 'Kira: düşükten yükseğe')," "(AdSpaceSort.priceAsc, 'Tutar: düşükten yükseğe')," 'etiket: tutar artan'

  # 3) Satirda tutari goster
  Edit-Once @'
              TextSpan(
                text:
                    'Bitiş: ${DateFormat('dd.MM.yyyy').format(contract.endDate)}\n',
              ),
'@ @'
              TextSpan(
                text:
                    'Bitiş: ${DateFormat('dd.MM.yyyy').format(contract.endDate)}\n',
              ),
              TextSpan(
                text:
                    'Tutar: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(contract.monthlyPrice)}\n',
              ),
'@ 'satir: Tutar bilgisi'
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
