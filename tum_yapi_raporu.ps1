<#
  tum_yapi_raporu.ps1
  Projenin TUM yapisini okumak icin rapor uretir (HICBIR DOSYAYI DEGISTIRMEZ).

  Onceki rapordan farklari:
   * Hicbir dosya satir sinirina takilmaz: lib altindaki her .dart dosyasi TAM icerigiyle yazilir.
   * Isim filtresi yok: tema, kenar cubugu, renkler, yardimcilar, servisler, testler dahil hepsi.
   * Rapor birden cok parcaya bolunur (varsayilan ~300 KB), dosyalar parcalar arasinda bolunmez.
   * Gizli anahtarlar (firebase_options.dart ve AIza... anahtarlari) maskelenir.

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\tum_yapi_raporu.ps1
  Parca boyutunu degistirmek icin:  ... -ParcaKB 200
#>
param(
  [string]$ProjeYolu = (Get-Location).Path,
  [int]$ParcaKB = 300
)

$ErrorActionPreference = 'Stop'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

# ---------------------------------------------------------------- proje koku
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($p) { $root = $p.DirectoryName } else { Write-Host 'pubspec.yaml bulunamadi. Script'i proje klasorunde calistirin.' -ForegroundColor Red; exit 1' }
$root = (Resolve-Path $root).Path
Write-Host "Proje: $root" -ForegroundColor Cyan

$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'proje_yapisi'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null

function Rel([string]$full) { return ($full.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/') }

function Is-Excluded([string]$full) {
  $r = Rel $full
  if ($r -match '(^|/)(build|\.dart_tool|\.git|\.idea|\.vscode|node_modules|\.gradle|Pods)(/|$)') { return $true }
  if ($r -match '(^|/)_yedek[^/]*(/|$)') { return $true }
  if ($r -match '(^|/)[^/]*_yedekler(/|$)') { return $true }
  if ($r -match '\.(g|freezed|mocks)\.dart$') { return $true }
  if ($r -match 'generated_plugin_registrant') { return $true }
  if ($r -match '\.yedek') { return $true }
  return $false
}

function Mask-Secrets([string]$text) {
  $text = [regex]::Replace($text, 'AIza[0-9A-Za-z_\-]{20,}', 'AIza***GIZLI***')
  return $text
}

# ---------------------------------------------------------------- dosya listeleri
$libFiles = @(Get-ChildItem (Join-Path $root 'lib') -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -eq '.dart' -and -not (Is-Excluded $_.FullName) })
$testFiles = @()
foreach ($d in 'test', 'integration_test') {
  $dp = Join-Path $root $d
  if (Test-Path $dp) {
    $testFiles += @(Get-ChildItem $dp -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq '.dart' -and -not (Is-Excluded $_.FullName) })
  }
}

# main.dart basa, sonra yola gore sirali
$sortKey = { $r = Rel $_.FullName; if ($r -eq 'lib/main.dart') { '0' } else { '1' + $r } }
$libFiles = @($libFiles | Sort-Object $sortKey)
$testFiles = @($testFiles | Sort-Object { Rel $_.FullName })

# kok dizin ve platform yapilandirma dosyalari (sirli olmayanlar)
$configCandidates = @(
  'pubspec.yaml', 'analysis_options.yaml', 'firebase.json', 'firestore.rules',
  'firestore.indexes.json', 'README.md', '.gitignore', 'devtools_options.yaml',
  'android/app/src/main/AndroidManifest.xml', 'android/app/build.gradle', 'android/app/build.gradle.kts',
  'android/build.gradle', 'android/build.gradle.kts', 'android/settings.gradle', 'android/settings.gradle.kts',
  'android/gradle.properties', 'windows/runner/Runner.rc', 'windows/CMakeLists.txt'
)
$configFiles = @()
foreach ($c in $configCandidates) {
  $p = Join-Path $root ($c -replace '/', '\')
  if (Test-Path $p) { $configFiles += Get-Item $p }
}

function Line-Count([string]$path) {
  try { return ([IO.File]::ReadAllLines($path)).Count } catch { return 0 }
}

# ---------------------------------------------------------------- 00_ozet.txt
$sb = New-Object System.Text.StringBuilder
function Add([string]$s) { [void]$script:sb.AppendLine($s) }

Add "=== RAPOR BILGISI ==="
Add ("Olusturulma : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add ("Proje koku  : " + $root)
Add ("lib/*.dart  : {0} dosya" -f $libFiles.Count)
Add ("test/*.dart : {0} dosya" -f $testFiles.Count)
Add ""

if (Get-Command flutter -ErrorAction SilentlyContinue) {
  Add "=== SURUMLER ==="
  try {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location $root
    $fv = & flutter --version 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -First 6
    Pop-Location
    $ErrorActionPreference = $prev
    foreach ($l in $fv) { Add $l }
  }
  catch { Add "(flutter --version alinamadi)" }
  Add ""
}

if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $root '.git'))) {
  Add "=== GIT ==="
  try {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location $root
    Add "--- son 15 commit ---"
    foreach ($l in (& git log --oneline -n 15 2>&1 | ForEach-Object { $_.ToString() })) { Add $l }
    Add "--- degisen dosyalar ---"
    foreach ($l in (& git status --short 2>&1 | ForEach-Object { $_.ToString() } | Select-Object -First 80)) { Add $l }
    Pop-Location
    $ErrorActionPreference = $prev
  }
  catch { Add "(git bilgisi alinamadi)" }
  Add ""
}

Add "=== DOSYA AGACI (satir sayisi ile) ==="
$total = 0
foreach ($f in ($configFiles + $libFiles + $testFiles)) {
  $n = Line-Count $f.FullName
  $total += $n
  Add ("{0,6}  {1}" -f $n, (Rel $f.FullName))
}
Add ("{0,6}  TOPLAM satir" -f $total)
Add ""

# varliklar (assets / fonts) - yalniz liste
foreach ($d in 'assets', 'fonts') {
  $dp = Join-Path $root $d
  if (Test-Path $dp) {
    Add "=== $d/ klasoru (yalniz dosya adlari) ==="
    foreach ($a in (Get-ChildItem $dp -Recurse -File | Select-Object -First 200)) {
      Add ("{0,9} B  {1}" -f $a.Length, (Rel $a.FullName))
    }
    Add ""
  }
}

# platform klasorleri
Add "=== PLATFORM KLASORLERI ==="
foreach ($pf in 'android', 'ios', 'windows', 'macos', 'linux', 'web') {
  if (Test-Path (Join-Path $root $pf)) { Add "  var: $pf" }
}
Add ""

Add "=== TANIM INDEKSI (sinif / enum / mixin / extension / typedef / ust duzey fonksiyon) ==="
$declRe = '^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+|interface\s+)*(class|enum|mixin|extension|typedef)\s+([A-Za-z_]\w*)'
$funcRe = '^(?:Future<[^>]*>|Future|void|String|bool|int|double|Widget|List<[^>]*>|Map<[^>]*>|Iterable<[^>]*>)\??\s+([A-Za-z_]\w*)\s*\('
foreach ($f in ($libFiles + $testFiles)) {
  $names = New-Object System.Collections.ArrayList
  foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
    $m = [regex]::Match($line, $declRe)
    if ($m.Success) { [void]$names.Add($m.Groups[1].Value + ' ' + $m.Groups[2].Value); continue }
    $m2 = [regex]::Match($line, $funcRe)
    if ($m2.Success) { [void]$names.Add('fn ' + $m2.Groups[1].Value + '()') }
  }
  if ($names.Count -gt 0) { Add ("{0}`n    {1}" -f (Rel $f.FullName), ($names -join '; ')) }
}
Add ""

Add "=== PROJE ICI IMPORT BAGLANTILARI (hangi dosya hangisini kullaniyor) ==="
foreach ($f in $libFiles) {
  $imports = @()
  foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
    $m = [regex]::Match($line, "^\s*(?:import|export)\s+'(?!package:|dart:)([^']+)'")
    if ($m.Success) { $imports += $m.Groups[1].Value }
  }
  if ($imports.Count -gt 0) { Add ("{0}`n    -> {1}" -f (Rel $f.FullName), ($imports -join ', ')) }
}
Add ""

Add "=== ONEMLI ARAMALAR (dosya:satir: icerik) ==="
$searches = [ordered]@{
  'FIRESTORE KOLEKSIYON / BELGE'   = '\.collection\(|\.doc\(|FirebaseFirestore'
  'SHARED PREFERENCES ANAHTARLARI' = "getString\(|setString\(|getInt\(|setInt\(|getBool\(|setBool\("
  'PLATFORM KONTROLLERI'           = 'Platform\.is|defaultTargetPlatform|kIsWeb'
  'ROUTE / NAVIGATOR'              = 'Navigator\.|MaterialPageRoute|onGenerateRoute'
}
foreach ($k in $searches.Keys) {
  Add ""
  Add "--- $k ---"
  $hits = $libFiles | Select-String -Pattern $searches[$k] -ErrorAction SilentlyContinue | Select-Object -First 200
  foreach ($h in $hits) {
    $t = $h.Line.Trim(); if ($t.Length -gt 150) { $t = $t.Substring(0, 150) }
    Add ("{0}:{1}: {2}" -f (Rel $h.Path), $h.LineNumber, $t)
  }
}
Add ""

# ---------------------------------------------------------------- kod parcalari
$limit = $ParcaKB * 1024
$parts = New-Object System.Collections.ArrayList
$cur = New-Object System.Text.StringBuilder
$curFiles = New-Object System.Collections.ArrayList
$partNo = 0

function Flush-Part {
  if ($script:cur.Length -eq 0) { return }
  $script:partNo++
  $name = ('{0:00}_kod_{1}.txt' -f $script:partNo, $script:partNo)
  $path = Join-Path $script:out $name
  [IO.File]::WriteAllText($path, $script:cur.ToString(), $script:utf8Bom)
  [void]$script:parts.Add(@{ Name = $name; Size = $script:cur.Length; Files = @($script:curFiles) })
  $script:cur = New-Object System.Text.StringBuilder
  $script:curFiles = New-Object System.Collections.ArrayList
}

foreach ($f in ($configFiles + $libFiles + $testFiles)) {
  $r = Rel $f.FullName
  $lines = $null
  if ($r -eq 'lib/firebase_options.dart') {
    $text = "// [ICERIK GIZLENDI: Firebase anahtarlari iceriyor. Dosya var; yalnizca DefaultFirebaseOptions sinifini barindirir.]"
  }
  else {
    $text = [IO.File]::ReadAllText($f.FullName)
    $text = Mask-Secrets $text
  }
  $text = $text -replace "`r`n", "`n"
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $n = ($text -split "`n").Count
  $block = "`n################################################################`n##### DOSYA: $r  ($n satir)`n################################################################`n" + $text.TrimEnd("`n") + "`n"
  if ($cur.Length -gt 0 -and ($cur.Length + $block.Length) -gt $limit) { Flush-Part }
  [void]$cur.Append($block)
  [void]$curFiles.Add($r)
}
Flush-Part

Add "=== KOD PARCALARI ==="
foreach ($p in $parts) {
  Add ("{0}  ({1} KB, {2} dosya)" -f $p.Name, [math]::Round($p.Size / 1KB), $p.Files.Count)
  foreach ($fn in $p.Files) { Add ("      " + $fn) }
}

[IO.File]::WriteAllText((Join-Path $out '00_ozet.txt'), $sb.ToString(), $utf8Bom)

# ---------------------------------------------------------------- sonuc
$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) 'proje_yapisi.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
try { Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force } catch { $zip = $null }

Write-Host ""
Write-Host "TAMAM" -ForegroundColor Green
Write-Host ("Klasor : {0}" -f $out)
if ($zip) { Write-Host ("Zip    : {0}" -f $zip) }
Write-Host ("Dosyalar: 00_ozet.txt + {0} kod parcasi" -f $parts.Count)
foreach ($p in $parts) { Write-Host ("  {0}  {1} KB" -f $p.Name, [math]::Round($p.Size / 1KB)) }
Write-Host ""
Write-Host "Klasordeki TUM .txt dosyalarini (00_ozet.txt dahil) sohbete yukleyin." -ForegroundColor Yellow
Write-Host "Not: firebase_options.dart ve AIza... anahtarlari rapora yazilmaz." -ForegroundColor DarkGray
Start-Process explorer.exe $out
