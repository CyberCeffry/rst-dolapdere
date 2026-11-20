<#
  mevcut_durum_raporu.ps1
  Amac: Flutter projesinin mevcut halini okumak (HICBIR DOSYAYI DEGISTIRMEZ).

  Kullanim (proje klasorunun icinde PowerShell acin):
      powershell -ExecutionPolicy Bypass -File .\mevcut_durum_raporu.ps1
  Baska bir yoldan:
      powershell -ExecutionPolicy Bypass -File .\mevcut_durum_raporu.ps1 -ProjeYolu "C:\proje\klasoru"
  Tum lib/*.dart dosyalarini dahil etmek icin:
      ... -TumKod
#>
param(
  [string]$ProjeYolu = (Get-Location).Path,
  [switch]$TumKod,
  [int]$DosyaBasinaMaksSatir = 1500
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($true)

# ---------- Proje kokunu bul ----------
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName }
  else { Write-Host "pubspec.yaml bulunamadi. Script'i proje klasorunde calistirin veya -ProjeYolu verin." -ForegroundColor Red; exit 1 }
}
$lib = Join-Path $root 'lib'
if (-not (Test-Path $lib)) { Write-Host "lib klasoru yok: $lib" -ForegroundColor Red; exit 1 }

$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'mevcut_durum'
New-Item -ItemType Directory -Force $out | Out-Null
$ozetYol = Join-Path $out '01_ozet.txt'
$kodYol  = Join-Path $out '02_kod.txt'

function Rel([string]$full) { return $full.Substring($root.Length).TrimStart('\') }

# ---------- Dart dosyalari ----------
$dosyalar = Get-ChildItem $lib -Recurse -Filter *.dart |
  Where-Object { $_.Name -notmatch '\.(g|freezed|mocks)\.dart$' -and $_.FullName -notmatch '\\(generated|l10n)\\' }

Write-Host ("Bulunan dart dosyasi: {0}" -f $dosyalar.Count) -ForegroundColor Cyan

# ---------- 01_ozet.txt ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("=== PROJE KOKU ===")
[void]$sb.AppendLine($root)
[void]$sb.AppendLine("")

[void]$sb.AppendLine("=== pubspec.yaml ===")
[void]$sb.AppendLine([IO.File]::ReadAllText((Join-Path $root 'pubspec.yaml')))
[void]$sb.AppendLine("")

[void]$sb.AppendLine("=== lib DOSYA AGACI (satir sayisi ile) ===")
foreach ($f in ($dosyalar | Sort-Object FullName)) {
  $n = ([IO.File]::ReadAllLines($f.FullName)).Count
  [void]$sb.AppendLine(("{0,6}  {1}" -f $n, (Rel $f.FullName)))
}
[void]$sb.AppendLine("")

# Android izinleri / servis (arka plan esitleme icin onemli)
$manifest = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
  [void]$sb.AppendLine("=== AndroidManifest.xml ===")
  [void]$sb.AppendLine([IO.File]::ReadAllText($manifest))
  [void]$sb.AppendLine("")
}

# Anahtar kelime aramalari
$aramalar = [ordered]@{
  'ARKA PLAN / PERIYODIK ESITLEME'   = 'Timer\.periodic|workmanager|Workmanager|flutter_background_service|FlutterBackgroundService|AppLifecycleState|WidgetsBindingObserver|isolate'
  'ESITLEME / SYNC'                  = '[Ss]ync|e.itle|Esitle'
  'PDF'                              = '\bpdf\b|Pdf|printing|Printing|OpenFile|open_file|launchUrl|Share\.'
  'TARIH ARALIGI'                    = 'showDateRangePicker|DateTimeRange|showDatePicker'
  'FILTRE / SIRALAMA'                = 'DropdownButton|FilterChip|ChoiceChip|SegmentedButton|\.sort\(|sorted|orderBy|ORDER BY|[Ff]iltre|[Ff]ilter'
  'COKLU SECIM'                      = 'Checkbox|selectedIds|secili|selection|isSelected|multi'
  'KALAN SURE'                       = '[Kk]alan'
  'AD SOYAD / FIRMA ALANLARI'        = 'Ad Soyad|Firma Ad|firmaAdi|adSoyad|ad_soyad|Adres|adres'
  'INCELE / DETAY / BILDIRIM'        = 'ncele|[Dd]etay|[Bb]ildirim|[Nn]otification'
}
[void]$sb.AppendLine("=== ANAHTAR KELIME ARAMALARI (dosya:satir: icerik) ===")
foreach ($k in $aramalar.Keys) {
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("--- $k ---")
  $hits = $dosyalar | Select-String -Pattern $aramalar[$k] -ErrorAction SilentlyContinue | Select-Object -First 250
  foreach ($h in $hits) {
    $t = $h.Line.Trim(); if ($t.Length -gt 160) { $t = $t.Substring(0,160) }
    [void]$sb.AppendLine(("{0}:{1}: {2}" -f (Rel $h.Path), $h.LineNumber, $t))
  }
}

# Git durumu (varsa)
if (Get-Command git -ErrorAction SilentlyContinue) {
  if (Test-Path (Join-Path $root '.git')) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("=== GIT DURUMU ===")
    Push-Location $root
    try {
      [void]$sb.AppendLine((git status --short 2>&1 | Out-String))
      [void]$sb.AppendLine((git log --oneline -n 10 2>&1 | Out-String))
    } finally { Pop-Location }
  }
}

[IO.File]::WriteAllText($ozetYol, $sb.ToString(), $utf8)

# ---------- 02_kod.txt : ilgili dosyalarin tam icerigi ----------
$isimDeseni  = 'm.steri|customer|client|s.zle.me|contract|bildirim|notification|e.itle|sync|firma|company|kirac|tenant|reklam|advert|alan|space|pdf|filter|filtre|sort|siralama|database|db_|_db|repository|service|provider|model|main|home|dashboard|settings|ayar'
$icerikDeseni = 'Timer\.periodic|workmanager|showDateRangePicker|DateTimeRange|pdf|Pdf|[Kk]alan|Ad Soyad|ncele'

$secilen = foreach ($f in $dosyalar) {
  if ($TumKod) { $f; continue }
  if ($f.Name -match $isimDeseni) { $f; continue }
  $m = Select-String -Path $f.FullName -Pattern $icerikDeseni -ErrorAction SilentlyContinue
  if (($m | Measure-Object).Count -ge 4) { $f }
}
$secilen = $secilen | Sort-Object FullName -Unique

$kodSb = New-Object System.Text.StringBuilder
foreach ($f in $secilen) {
  $satirlar = [IO.File]::ReadAllLines($f.FullName)
  [void]$kodSb.AppendLine("")
  [void]$kodSb.AppendLine("################################################################")
  [void]$kodSb.AppendLine("##### DOSYA: " + (Rel $f.FullName) + "  (" + $satirlar.Count + " satir)")
  [void]$kodSb.AppendLine("################################################################")
  if ($satirlar.Count -gt $DosyaBasinaMaksSatir) {
    [void]$kodSb.AppendLine(($satirlar[0..($DosyaBasinaMaksSatir-1)] -join "`r`n"))
    [void]$kodSb.AppendLine("... [KIRPILDI: toplam " + $satirlar.Count + " satir] ...")
  } else {
    [void]$kodSb.AppendLine(($satirlar -join "`r`n"))
  }
}
[IO.File]::WriteAllText($kodYol, $kodSb.ToString(), $utf8)

$boyutMB = [math]::Round((Get-Item $kodYol).Length / 1MB, 2)
Write-Host ""
Write-Host "TAMAM" -ForegroundColor Green
Write-Host ("Ozet : {0}" -f $ozetYol)
Write-Host ("Kod  : {0}  ({1} dosya, {2} MB)" -f $kodYol, @($secilen).Count, $boyutMB)
Write-Host ""
Write-Host "01_ozet.txt ve 02_kod.txt dosyalarini sohbete yukleyin (cok buyukse once 02_kod.txt'yi iki parcaya bolebilirsiniz)." -ForegroundColor Yellow
Start-Process explorer.exe $out
