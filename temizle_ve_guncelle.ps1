# RST Dolapdere - Auth / Cloud Functions temizligi ve guncelleme scripti
#
# KULLANIM:
#   1) guncel_dosyalar.zip ile bu dosyayi AYNI klasore koyun (ornegin Downloads).
#   2) PowerShell'i proje ana dizininde acin (pubspec.yaml'in oldugu klasor).
#   3) Calistirin (yolu kendinize gore degistirin):
#        powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\temizle_ve_guncelle.ps1"
#
# Script once yedek alir, sonra dosyalari gunceller, auth ve cloud function
# dosyalarini siler, pubspec.yaml / firebase.json dosyalarini temizler ve
# flutter pub get + flutter analyze calistirir.

$ErrorActionPreference = "Stop"
$root = (Get-Location).Path
$zip  = Join-Path $PSScriptRoot "guncel_dosyalar.zip"
if (-not (Test-Path $zip)) { $zip = Join-Path $root "guncel_dosyalar.zip" }

function Adim($t) { Write-Host ""; Write-Host ">> $t" -ForegroundColor Cyan }

if (-not (Test-Path (Join-Path $root "pubspec.yaml"))) {
    Write-Host "HATA: pubspec.yaml bulunamadi. Scripti proje ana dizininde calistirin." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $zip)) {
    Write-Host "HATA: guncel_dosyalar.zip bulunamadi (script ile ayni klasorde olmali)." -ForegroundColor Red
    exit 1
}

# 1) YEDEK -------------------------------------------------------------------
Adim "Yedek aliniyor"
# Yedek proje klasorunun DISINA alinir (flutter analyze yedegi taramasin diye).
$bak = Join-Path ([Environment]::GetFolderPath("Desktop")) ("rst_yedek_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $bak | Out-Null
robocopy "$root\lib" "$bak\lib" /E /NFL /NDL /NJH /NJS /NP | Out-Null
if (Test-Path "$root\test")      { robocopy "$root\test" "$bak\test" /E /NFL /NDL /NJH /NJS /NP | Out-Null }
if (Test-Path "$root\functions") { robocopy "$root\functions" "$bak\functions" /E /XD node_modules /NFL /NDL /NJH /NJS /NP | Out-Null }
foreach ($f in @("pubspec.yaml", "firebase.json")) {
    if (Test-Path "$root\$f") { Copy-Item "$root\$f" "$bak\$f" }
}
Write-Host "Yedek: $bak"

# 2) YENI DOSYALARI ACMA ------------------------------------------------------
Adim "Guncel dosyalar kopyalaniyor"
Expand-Archive -Path $zip -DestinationPath $root -Force

# 3) GEREKSIZ DOSYALARI SILME -------------------------------------------------
Adim "Auth ve Cloud Functions dosyalari siliniyor"
$silinecek = @(
    "lib\core\services\auth_service.dart",
    "lib\features\auth",
    "lib\features\settings\screens\admin_workspace_panel.dart",
    "lib\models\app_user.dart",
    "lib\core\services\ap_store_yedek",
    "test\app_role_permissions_test.dart",
    "functions"
)
foreach ($rel in $silinecek) {
    $p = Join-Path $root $rel
    if (Test-Path $p) {
        if ((Get-Item $p).PSIsContainer) { cmd /c rmdir /s /q "`"$p`"" } else { Remove-Item $p -Force }
        Write-Host "silindi: $rel"
    }
}

# 3b) Silinen siniflari kullanan testleri sil
$testler = Get-ChildItem "$root\test" -Recurse -Filter *.dart -ErrorAction SilentlyContinue |
    Select-String -Pattern 'AppUser|AppRole|app_user.dart|auth_service.dart' | Select-Object -ExpandProperty Path -Unique
foreach ($tf in $testler) { Remove-Item $tf -Force; Write-Host ("silindi (test): " + $tf) }

# 4) pubspec.yaml TEMIZLIGI ---------------------------------------------------
Adim "pubspec.yaml temizleniyor"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pub = Join-Path $root "pubspec.yaml"
$satirlar = [System.IO.File]::ReadAllLines($pub)
$yeni = $satirlar | Where-Object { $_ -notmatch '^\s*(firebase_auth|cloud_functions|firebase_messaging)\s*:' }
[System.IO.File]::WriteAllLines($pub, $yeni, $utf8)
Write-Host ("kaldirilan paket satiri: " + ($satirlar.Count - $yeni.Count))

# 5) firebase.json -> functions bolumunu kaldir -------------------------------
$fj = Join-Path $root "firebase.json"
if (Test-Path $fj) {
    Adim "firebase.json temizleniyor"
    $j = [System.IO.File]::ReadAllText($fj) | ConvertFrom-Json
    if ($j.PSObject.Properties.Name -contains "functions") {
        $j.PSObject.Properties.Remove("functions")
        [System.IO.File]::WriteAllText($fj, ($j | ConvertTo-Json -Depth 20), $utf8)
        Write-Host "functions bolumu kaldirildi."
    }
}

# 5b) Proje icinde kalmis eski yedek klasorlerini Masaustune tasi
Get-ChildItem $root -Directory -Filter "yedek_*" -ErrorAction SilentlyContinue | ForEach-Object {
    Move-Item $_.FullName (Join-Path ([Environment]::GetFolderPath("Desktop")) ("rst_" + $_.Name)) -Force
    Write-Host ("tasindi: " + $_.Name)
}

# 6) PAKETLER + ANALIZ --------------------------------------------------------
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "UYARI: flutter komutu bulunamadi; pub get ve analyze atlandi." -ForegroundColor Yellow
    exit 0
}
Adim "flutter pub get"
flutter pub get
Adim "flutter analyze"
flutter analyze

# 7) KALINTI KONTROLU ---------------------------------------------------------
Adim "Kalinti kontrolu"
$kalinti = Get-ChildItem "$root\lib","$root\test" -Recurse -Filter *.dart -ErrorAction SilentlyContinue |
    Select-String -Pattern 'firebase_auth|cloud_functions|firebase_messaging|AuthService|AppRole|AppUser'
if ($kalinti) { $kalinti | ForEach-Object { Write-Host ("{0}:{1}" -f $_.Path, $_.LineNumber) } }
else { Write-Host "Auth / Cloud Functions kalintisi yok." -ForegroundColor Green }

Write-Host ""
Write-Host "Bitti. Sorun yoksa: flutter run" -ForegroundColor Green
Write-Host "Geri almak icin yedek klasoru: $bak"
