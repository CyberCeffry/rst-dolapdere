<#
.SYNOPSIS
    Kalan sure gosterimini "X ay Y gun" olarak duzeltir (RST Dolapdere).

.DESCRIPTION
    30 gunden uzun kalan surelerde "Aktif • 1 ay 10 gün kaldı" / "6 ay 3 gün" gibi
    ay + gun yazar (tam ay ise sadece ay). Once sozlesme_gorunum_duzeltme.ps1 uygulanmis olmalidir.
    Dosya degistirilmeden once yedeklenir; kod bulunamazsa hicbir sey degismez.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\sozlesme_kalan_sure_duzeltme.ps1 -ProjectPath "C:\Users\USER\Desktop\git-desktop\rst-dolapdere"
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
  String _activeStatus(DateTime endDate, int days) {
    if (days <= 30) return 'Aktif • $days gün kaldı';
    final today = DateTime.now();
    var months =
        (endDate.year - today.year) * 12 + endDate.month - today.month;
    if (endDate.day < today.day) months--;
    if (months < 1) months = 1;
    return 'Aktif • $months ay kaldı';
  }
'@
$new = @'
  String _activeStatus(DateTime endDate, int days) {
    if (days <= 30) return 'Aktif • $days gün kaldı';
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    var months = (end.year - today.year) * 12 + end.month - today.month;
    if (end.day < today.day) months--;
    if (months < 1) return 'Aktif • $days gün kaldı';
    // Bugünden "months" ay sonrası (ay sonuna taşarsa ayın son günü).
    final anchorMonth = today.month + months;
    final lastDay = DateTime.utc(today.year, anchorMonth + 1, 0).day;
    final anchor = DateTime.utc(
      today.year,
      anchorMonth,
      today.day > lastDay ? lastDay : today.day,
    );
    final extraDays = end.difference(anchor).inDays;
    return extraDays > 0
        ? 'Aktif • $months ay $extraDays gün kaldı'
        : 'Aktif • $months ay kaldı';
  }
'@
Add-Patch 'lib\features\records\management_screens.dart' 'Kalan süre: ay + gün' $old $new

$old = @'
          width: 210,

'@
$new = @'
          width: 250,

'@
Add-Patch 'lib\features\records\management_screens.dart' 'Kalan süre: alan genişliği' $old $new

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

if ($files[$screenRel].Text.Contains('extraDays')) {
    Write-Host 'Bu duzeltme zaten uygulanmis gorunuyor (management_screens.dart). Islem yapilmadi.' -ForegroundColor Yellow
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
$backupRoot = Join-Path $ProjectPath ".yedek_kalan_sure_$stamp"
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
