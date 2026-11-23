<#
  yama_kalan_sure_detay.ps1
  Reklam alani ve sozlesme PDF'lerinde "Kalan sure" sutunu, sozlesme ekranindaki
  gibi ayrintili yazilir:  "1 ay 8 gun",  "2 ay",  "25 gun".

  Kullanim (proje klasorunde):
      powershell -ExecutionPolicy Bypass -File .\yama_kalan_sure_detay.ps1
#>
param([string]$ProjeYolu = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$root = $ProjeYolu
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
  $p = Get-ChildItem $root -Filter pubspec.yaml -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $root = $p.DirectoryName } else { Write-Host 'pubspec.yaml bulunamadi.' -ForegroundColor Red; exit 1 }
}

$F_REM = 'lib\core\utils\contract_remaining_time.dart'
$F_AD = 'lib\features\records\services\ad_space_pdf_service.dart'
$F_PDF = 'lib\features\contracts\services\contract_pdf_service.dart'

$script:buf = @{}; $script:meta = @{}

function Load-File([string]$rel) {
  $path = Join-Path $root $rel
  if (-not (Test-Path $path)) { throw "Dosya bulunamadi: $rel" }
  $bytes = [IO.File]::ReadAllBytes($path)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  if ($bom) { $text = $text.Substring(1) }
  $script:meta[$rel] = @{ Bom = $bom; Crlf = $text.Contains("`r`n"); Path = $path }
  $script:buf[$rel] = $text -replace "`r`n", "`n"
}

function Edit-Once([string]$rel, [string]$old, [string]$new, [string]$what) {
  $old = $old -replace "`r`n", "`n"; $new = $new -replace "`r`n", "`n"
  $t = $script:buf[$rel]
  $i = $t.IndexOf($old, [StringComparison]::Ordinal)
  if ($i -lt 0) { throw "[$rel] baglanti noktasi bulunamadi: $what" }
  if ($t.IndexOf($old, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "[$rel] birden fazla eslesme: $what" }
  $script:buf[$rel] = $t.Substring(0, $i) + $new + $t.Substring($i + $old.Length)
  Write-Host "  + $what" -ForegroundColor DarkGreen
}

try {
  foreach ($f in @($F_REM, $F_AD, $F_PDF)) { Load-File $f }
  if ($script:buf[$F_REM].Contains('formatDetailed')) {
    Write-Host 'Yama zaten uygulanmis.' -ForegroundColor Yellow; exit 0
  }

  # 1) Ortak yardimci (sozlesme ekranindaki _activeStatus ile ayni mantik)
  Edit-Once $F_REM '  static bool isUrgent(int days) => days >= 0 && days < 15;' @'
  static bool isUrgent(int days) => days >= 0 && days < 15;

  /// Ayrıntılı kalan süre: "25 gün", "1 ay 8 gün", "3 ay".
  /// Sözleşmeler ekranındaki "Aktif • 1 ay 8 gün kaldı" ile aynı hesabı yapar.
  static String formatDetailed(DateTime endDate, {DateTime? today}) {
    final days = daysUntil(endDate, today: today);
    if (days <= 30) return '$days gün';
    final now = today ?? DateTime.now();
    final start = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    var months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day < start.day) months--;
    if (months < 1) return '$days gün';
    // Bugünden "months" ay sonrası (ay sonuna taşarsa ayın son günü).
    final anchorMonth = start.month + months;
    final lastDay = DateTime.utc(start.year, anchorMonth + 1, 0).day;
    final anchor = DateTime.utc(
      start.year,
      anchorMonth,
      start.day > lastDay ? lastDay : start.day,
    );
    final extraDays = end.difference(anchor).inDays;
    return extraDays > 0 ? '$months ay $extraDays gün' : '$months ay';
  }
'@ 'ContractRemainingTime.formatDetailed'

  # 2) Reklam alanlari PDF
  Edit-Once $F_AD "days == null ? '-' : ContractRemainingTime.format(days)," "contract == null ? '-' : ContractRemainingTime.formatDetailed(contract.endDate)," 'reklam alani PDF: kalan sure'

  # 3) Sozlesme PDF
  Edit-Once $F_PDF '    return ContractRemainingTime.format(days);' '    return ContractRemainingTime.formatDetailed(contract.endDate);' 'sozlesme PDF: kalan sure'
}
catch {
  Write-Host "`nHATA: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Hicbir dosya degistirilmedi. Bu mesaji bana gonderin.' -ForegroundColor Yellow
  exit 1
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
foreach ($f in @($F_REM, $F_AD, $F_PDF)) {
  $m = $script:meta[$f]
  Copy-Item $m.Path "$($m.Path).yedek_$stamp" -Force
  $text = $script:buf[$f]
  if ($m.Crlf) { $text = $text -replace "`n", "`r`n" }
  [IO.File]::WriteAllText($m.Path, $text, (New-Object Text.UTF8Encoding($m.Bom)))
  Write-Host "  yazildi: $f" -ForegroundColor DarkGreen
}
Write-Host "`nBITTI. Yedekler: *.yedek_$stamp" -ForegroundColor Green
