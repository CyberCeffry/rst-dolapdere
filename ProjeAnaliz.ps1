
param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"

$ProjectPath = (Resolve-Path $ProjectPath).Path
$ReportPath = Join-Path $ProjectPath "proje_analiz_raporu.txt"

"FLUTTER PROJE ANALİZ RAPORU" | Out-File $ReportPath -Encoding utf8
"Proje: $ProjectPath" | Out-File $ReportPath -Append -Encoding utf8

"`n=== PROJE DOSYA YAPISI ===" |
    Out-File $ReportPath -Append -Encoding utf8

Get-ChildItem $ProjectPath -Recurse -File |
Where-Object {
    $_.FullName -notmatch '\\(build|\.dart_tool|\.git|windows\\flutter|android\\\.gradle)\\' -and
    ($_.Extension -in @('.dart','.yaml','.json','.sql','.ps1') -or
     $_.Name -in @('pubspec.yaml','README.md'))
} |
ForEach-Object {
    $_.FullName.Replace($ProjectPath, '')
} |
Out-File $ReportPath -Append -Encoding utf8

"`n=== ÖNEMLİ DART DOSYALARININ İÇERİĞİ ===" |
    Out-File $ReportPath -Append -Encoding utf8

$Files = Get-ChildItem $ProjectPath -Recurse -File -Filter "*.dart" |
Where-Object {
    $_.FullName -notmatch '\\(build|\.dart_tool|\.git)\\'
}

$Keywords = 'sozlesme|sözleşme|kiraci|kiracı|firma|pdf|database|sqlite|insert|update|create table'

foreach ($File in $Files) {

    $Content = Get-Content $File.FullName -Raw

    if ($Content -match $Keywords) {

        "`n----------------------------------------" |
            Out-File $ReportPath -Append -Encoding utf8

        "DOSYA: $($File.FullName)" |
            Out-File $ReportPath -Append -Encoding utf8

        $Content |
            Out-File $ReportPath -Append -Encoding utf8
    }
}

"`n=== PUBSPEC.YAML ===" |
    Out-File $ReportPath -Append -Encoding utf8

$Pubspec = Join-Path $ProjectPath "pubspec.yaml"

if (Test-Path $Pubspec) {
    Get-Content $Pubspec |
        Out-File $ReportPath -Append -Encoding utf8
}

Write-Host "Analiz tamamlandı." -ForegroundColor Green
Write-Host "Rapor: $ReportPath" -ForegroundColor Cyan
