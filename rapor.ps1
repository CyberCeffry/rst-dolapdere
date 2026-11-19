$ErrorActionPreference = "SilentlyContinue"
$root = (Get-Location).Path
$out  = Join-Path $root "proje_raporu.txt"
"" | Out-File $out -Encoding utf8

function Yaz($t)    { $t | Out-File $out -Append -Encoding utf8 }
function Baslik($t) { Yaz ""; Yaz ("=" * 80); Yaz $t; Yaz ("=" * 80) }
function Rel($p)    { $p.Substring($root.Length).TrimStart('\') }

function DosyaYaz($path) {
    if (Test-Path $path) {
        Baslik ("DOSYA: " + (Rel (Resolve-Path $path).Path))
        $c = Get-Content $path -Raw -Encoding UTF8
        $c = $c -replace 'AIza[0-9A-Za-z_\-]{35}', 'AIza***GIZLI***'
        Yaz $c
    } 
}

if (-not (Test-Path "$root\pubspec.yaml")) {
    Write-Host "HATA: pubspec.yaml bulunamadi. Scripti proje ana dizininde calistirin." -ForegroundColor Red
    exit
}

# 1) Flutter surumu
Baslik "FLUTTER / DART SURUMU"
Yaz ((flutter --version 2>&1) | Out-String)

# 2) pubspec
DosyaYaz "$root\pubspec.yaml"

# 3) lib dosya agaci
Baslik "LIB DOSYA AGACI (boyut bayt)"
Get-ChildItem "$root\lib" -Recurse -File | ForEach-Object {
    Yaz ("{0}  ({1})" -f (Rel $_.FullName), $_.Length)
}

# 4) Firebase / Firestore / Auth kullanim noktalari
Baslik "FIREBASE KULLANIM NOKTALARI (dosya:satir: icerik)"
$desen = 'snapshots\(|\.get\(|\.listen\(|StreamBuilder|StreamProvider|FirebaseAuth|signIn|authStateChanges|currentUser|enablePersistence|persistenceEnabled|cacheSizeBytes|Settings\(|FirebaseFirestore|collection\(|\.doc\(|\.set\(|\.update\(|\.delete\(|\.add\(|Timer\.periodic|Source\.cache|Source\.server|firebase_auth|cloud_firestore'
Get-ChildItem "$root\lib" -Recurse -Filter *.dart | Select-String -Pattern $desen | ForEach-Object {
    Yaz ("{0}:{1}: {2}" -f (Rel $_.Path), $_.LineNumber, $_.Line.Trim())
}

# 5) Firebase ve platform ayar dosyalari
$ayar = @(
    "$root\firebase.json",
    "$root\firestore.rules",
    "$root\firestore.indexes.json",
    "$root\lib\firebase_options.dart",
    "$root\android\app\build.gradle",
    "$root\android\app\build.gradle.kts",
    "$root\android\settings.gradle",
    "$root\android\settings.gradle.kts",
    "$root\android\app\src\main\AndroidManifest.xml",
    "$root\android\app\google-services.json"
)
foreach ($a in $ayar) { DosyaYaz $a }

# 6) Tum Dart dosyalari (uretilen dosyalar haric)
Baslik "TUM DART KODLARI"
Get-ChildItem "$root\lib" -Recurse -Filter *.dart |
    Where-Object { $_.Name -notmatch '\.(g|freezed)\.dart$' -and $_.Name -ne 'firebase_options.dart' } |
    ForEach-Object { DosyaYaz $_.FullName }

$boyut = [math]::Round((Get-Item $out).Length / 1KB)
Write-Host "Tamamlandi: $out ($boyut KB)" -ForegroundColor Green