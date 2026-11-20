<#
.SYNOPSIS
    Sozlesme listesi duzeltmeleri (RST Dolapdere / dere_sozlesme_takip).

.DESCRIPTION
    1) "Sozlesme aktif" anahtari: kapatilan sozlesme listede artik "Pasif" gorunur
       (once durum yazisi anahtari dikkate almadigi icin hep "Aktif" yaziyordu).
    2) Listede "Aktif" yazisinin yanina kalan sure eklenir:
         - 30 gun ve alti : "Aktif • 25 gün kaldı"
         - 30 gunden fazla: "Aktif • 5 ay kaldı"
       10 gun ve altindaki mevcut gosterim (kirmizi, "N gün kaldı") degismez.
    3) Girilen tutar TOPLAM tutar oldugu icin "/ ay" ve "Aylik" ifadeleri
       "Toplam tutar" olarak degistirilir (liste, detay, form, panel).

    Dosyalar degistirilmeden once .yedek_gorunum_<tarih> klasorune yedeklenir.
    Zorunlu bir kod parcasi bulunamazsa HICBIR dosya degistirilmez.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\sozlesme_gorunum_duzeltme.ps1 -ProjectPath "C:\Users\USER\Desktop\git-desktop\rst-dolapdere"
#>
[CmdletBinding()]
param(
    [string]$ProjectPath,
    [switch]$Analyze
)

$ErrorActionPreference = 'Stop'

$probe = 'ü'
if ($probe.Length -ne 1 -or [int][char]$probe[0] -ne 252) {
    Write-Host 'HATA: Bu dosya UTF-8 (BOM ile) kaydedilmemis. Dosyayi indirip dogrudan calistirin.' -ForegroundColor Red
    exit 1
}

function Test-ProjectRoot([string]$path) {
    return ($path -and (Test-Path (Join-Path $path 'pubspec.yaml')) -and
            (Test-Path (Join-Path $path 'lib\features\records\management_screens.dart')))
}
if (-not $ProjectPath) {
    if ($PSScriptRoot -and (Test-ProjectRoot $PSScriptRoot)) { $ProjectPath = $PSScriptRoot }
    else { $ProjectPath = (Get-Location).Path }
}
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-ProjectRoot $ProjectPath)) {
    Write-Host "HATA: '$ProjectPath' Flutter proje klasoru gibi gorunmuyor. -ProjectPath ile belirtin." -ForegroundColor Red
    exit 1
}
Write-Host "Proje: $ProjectPath" -ForegroundColor Cyan

function Read-Source([string]$fullPath) {
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $raw = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $raw = $raw.Substring(1) }
    $eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{ Text = $raw.Replace("`r`n", "`n"); Eol = $eol; HasBom = $hasBom }
}

function Write-Source([string]$fullPath, [string]$text, [string]$eol, [bool]$hasBom) {
    $out = $text
    if ($eol -eq "`r`n") { $out = $out.Replace("`n", "`r`n") }
    [System.IO.File]::WriteAllText($fullPath, $out, (New-Object System.Text.UTF8Encoding($hasBom)))
}

function Get-Count([string]$text, [string]$needle) {
    $n = 0; $i = 0
    while (($i = $text.IndexOf($needle, $i, [System.StringComparison]::Ordinal)) -ge 0) { $n++; $i += $needle.Length }
    return $n
}

$exact = New-Object System.Collections.ArrayList
$regex = New-Object System.Collections.ArrayList
function Add-Patch([string]$file, [string]$name, [string]$old, [string]$new) {
    [void]$exact.Add([pscustomobject]@{ File = $file; Name = $name; Old = $old.Replace("`r`n", "`n"); New = $new.Replace("`r`n", "`n") })
}
function Add-Regex([string]$file, [string]$name, [string]$pattern, [string]$replacement, [bool]$required) {
    [void]$regex.Add([pscustomobject]@{ File = $file; Name = $name; Pattern = $pattern.Replace("`r`n", "`n"); Replacement = $replacement; Required = $required })
}

$old = @'
          : days <= 10
          ? '$days
'@
$new = @'
          : !contract.isActive
          ? 'Pasif'
          : days <= 10
          ? '$days
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Durum: Pasif etiketi' $old $new

$old = @'
          : 'Aktif';
      statusColor = contract.isFinalized || days < 0
'@
$new = @'
          : _activeStatus(contract.endDate, days);
      statusColor = contract.isFinalized || !contract.isActive || days < 0
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Durum: Aktif + kalan süre' $old $new

$old = @'
  String _recordTitle(dynamic record) {
'@
$new = @'
  /// Aktif sözleşme için kalan süre: 30 gün ve altı gün, üstü ay olarak yazılır.
  /// (10 gün ve altındaki gösterim ayrı dalda, olduğu gibi kalır.)
  String _activeStatus(DateTime endDate, int days) {
    if (days <= 30) return 'Aktif • $days gün kaldı';
    final today = DateTime.now();
    var months =
        (endDate.year - today.year) * 12 + endDate.month - today.month;
    if (endDate.day < today.day) months--;
    if (months < 1) months = 1;
    return 'Aktif • $months ay kaldı';
  }

  String _recordTitle(dynamic record) {
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Durum: yardımcı metot' $old $new

$old = @'
        trailing: SizedBox(
          width: 130,
'@
$new = @'
        trailing: SizedBox(
          width: 210,
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Durum: sağ alan genişliği' $old $new

$old = @'
.format(contract.monthlyPrice)} / ay'
'@
$new = @'
.format(contract.monthlyPrice)}'
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Tutar: listede / ay kaldır' $old $new

$pat = @'
Ayl\S{1,4}k bedel:
'@
$rep = @'
Toplam tutar:
'@
Add-Regex 'lib\features\records\management_screens.dart' 'Tutar: detay etiketi' $pat $rep $true

$pat = @'
Ayl\S{1,4}k bedel:
'@
$rep = @'
Toplam tutar:
'@
Add-Regex 'lib\shared\layouts\main_layout.dart' 'Tutar: panel etiketi' $pat $rep $false

$pat = @'
(_textField\(\s*)'Ayl[^']*kira \([^']*\)',(\s*_price,\s*required: true,)
'@
$rep = @'
${1}'Toplam tutar (₺)',${2}
'@
Add-Regex 'lib\features\records\management_screens.dart' 'Tutar: form etiketi' $pat $rep $true

# ---------------------------------------------------------------------------
# Uygulama: once bellekte dene, sonra yedekle ve yaz
# ---------------------------------------------------------------------------
$screenRel = 'lib\features\records\management_screens.dart'
$files = @{}
$allFiles = @($exact | ForEach-Object { $_.File }) + @($regex | ForEach-Object { $_.File }) | Select-Object -Unique
$alreadyDone = $false

foreach ($rel in $allFiles) {
    $full = Join-Path $ProjectPath $rel
    if (-not (Test-Path -LiteralPath $full)) {
        $isRequired = ($exact | Where-Object { $_.File -eq $rel }) -or ($regex | Where-Object { $_.File -eq $rel -and $_.Required })
        if ($isRequired) { Write-Host "HATA: Dosya bulunamadi: $rel" -ForegroundColor Red; exit 1 }
        Write-Host "  Atlandi (dosya yok): $rel" -ForegroundColor Yellow
        continue
    }
    $files[$rel] = Read-Source $full
}

if ($files[$screenRel].Text.Contains('_activeStatus(')) {
    Write-Host 'Duzeltmeler zaten uygulanmis gorunuyor (management_screens.dart). Islem yapilmadi.' -ForegroundColor Yellow
    exit 0
}

$failed = @()
foreach ($p in $exact) {
    $src = $files[$p.File]
    $count = Get-Count $src.Text $p.Old
    if ($count -ne 1) { $failed += "  - [$($p.File)] $($p.Name): $count eslesme (1 olmaliydi)"; continue }
    $idx = $src.Text.IndexOf($p.Old, [System.StringComparison]::Ordinal)
    $src.Text = $src.Text.Substring(0, $idx) + $p.New + $src.Text.Substring($idx + $p.Old.Length)
}
foreach ($p in $regex) {
    if (-not $files.ContainsKey($p.File)) { continue }
    $src = $files[$p.File]
    $count = [regex]::Matches($src.Text, $p.Pattern).Count
    if ($count -lt 1) {
        if ($p.Required) { $failed += "  - [$($p.File)] $($p.Name): eslesme yok" }
        else { Write-Host "  Bilgi: [$($p.File)] $($p.Name): eslesme yok, atlandi." -ForegroundColor Yellow }
        continue
    }
    $src.Text = [regex]::Replace($src.Text, $p.Pattern, $p.Replacement)
}
if ($failed.Count -gt 0) {
    Write-Host 'HATA: Asagidaki kod parcalari bulunamadi. Hicbir dosya degistirilmedi:' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $ProjectPath ".yedek_gorunum_$stamp"
foreach ($rel in $files.Keys) {
    $dest = Join-Path $backupRoot $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectPath $rel) -Destination $dest -Force
}
try {
    foreach ($rel in $files.Keys) {
        $src = $files[$rel]
        Write-Source (Join-Path $ProjectPath $rel) $src.Text $src.Eol $src.HasBom
        Write-Host "  Guncellendi: $rel" -ForegroundColor Green
    }
}
catch {
    Write-Host "HATA: Yazma sirasinda sorun olustu, yedekten geri aliniyor: $($_.Exception.Message)" -ForegroundColor Red
    foreach ($rel in $files.Keys) { Copy-Item -LiteralPath (Join-Path $backupRoot $rel) -Destination (Join-Path $ProjectPath $rel) -Force }
    exit 1
}

Write-Host ''
Write-Host "Tamamlandi. Yedek: $backupRoot" -ForegroundColor Cyan
if ($Analyze) { Push-Location $ProjectPath; try { flutter analyze } finally { Pop-Location } }
else { Write-Host 'Sonraki adim: flutter analyze ; flutter run -d windows' -ForegroundColor Cyan }
