# =====================================================================
#  yama_baslamasina_kalan.ps1   (6. yama)
#  - Baslangic tarihi gelmemis sozlesmelerde "Aktif ... kaldi" yerine
#    "Baslamasina X ay Y gun var" yazilir:
#      sozlesme karti, sozlesme detayi, musteri detayi ve sozlesme PDF'i
#
#  ON KOSUL: yama_taksit5_pdf_son_odeme.ps1 uygulanmis olmali.
#
#  KULLANIM (proje kokunden):
#     powershell -ExecutionPolicy Bypass -File .\yama_baslamasina_kalan.ps1
#
#  KODLAMA GUVENLIGI:
#   * Bu dosya SADECE ASCII karakter icerir; Turkce karakterler \uXXXX
#     olarak yazilidir ve calisirken gercek karaktere cevrilir.
#   * Dart dosyalari .NET ile UTF-8 okunur/yazilir (Get-Content / Set-Content yok).
#   * CRLF/LF ve BOM durumu aynen korunur.
#   * Once tum yamalar bellekte dogrulanir; biri uymazsa HICBIR dosya yazilmaz.
# =====================================================================
param(
    [string]$Root = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Un([string]$s) {
    $s = $s.Replace("`r`n", "`n")
    $ev = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    return [regex]::Replace($s, '\\u([0-9A-Fa-f]{4})', $ev)
}

$patches = New-Object System.Collections.ArrayList

function Add-Replace([string]$file, [string]$anchor, [string]$text) {
    [void]$patches.Add([pscustomobject]@{ File = $file; Anchor = (Un $anchor); Text = (Un $text) })
}

# ---------------------------------------------------------------------
# YAMA TANIMLARI
# ---------------------------------------------------------------------
$a = @'
      final days = DateHelper.daysUntil(contract.endDate);
      title = space?.name ?? 'Reklam alan\u0131';
'@
$r = @'
      final days = DateHelper.daysUntil(contract.endDate);
      final startsLater = DateHelper.daysUntil(contract.startDate) > 0;
      title = space?.name ?? 'Reklam alan\u0131';
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
          : !contract.isActive
          ? 'Pasif'
          : days <= 10
          ? '$days g\u00FCn kald\u0131'
          : _activeStatus(contract.endDate, days);
'@
$r = @'
          : !contract.isActive
          ? 'Pasif'
          : startsLater
          ? 'Ba\u015Flamas\u0131na ${ContractRemainingTime.formatDetailed(contract.startDate)} var'
          : days <= 10
          ? '$days g\u00FCn kald\u0131'
          : _activeStatus(contract.endDate, days);
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
      statusColor = contract.isFinalized || !contract.isActive || days < 0
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : days <= 10
          ? AppColors.danger
          : AppColors.success;
'@
$r = @'
      statusColor = contract.isFinalized || !contract.isActive || days < 0
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : startsLater
          ? AppColors.info
          : days <= 10
          ? AppColors.danger
          : AppColors.success;
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
  if (days == 0) return 'Bug\u00FCn bitiyor';
  return ContractRemainingTime.format(days);
'@
$r = @'
  if (DateHelper.daysUntil(contract.startDate) > 0) {
    return 'Ba\u015Flamas\u0131na '
        '${ContractRemainingTime.formatDetailed(contract.startDate)} var';
  }
  if (days == 0) return 'Bug\u00FCn bitiyor';
  return ContractRemainingTime.format(days);
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
                    : startsLater
                    ? 'Ba\u015Flayacak'
                    : ContractRemainingTime.format(days);
'@
$r = @'
                    : startsLater
                    ? 'Ba\u015Flamas\u0131na ${ContractRemainingTime.formatDetailed(contract.startDate)} var'
                    : ContractRemainingTime.format(days);
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
    if (days < 0) return '-';
    if (days == 0) return 'Bug\u00FCn';
'@
$r = @'
    if (days < 0) return '-';
    if (DateHelper.daysUntil(contract.startDate) > 0) {
      return 'Ba\u015Flamas\u0131na '
          '${ContractRemainingTime.formatDetailed(contract.startDate)} var';
    }
    if (days == 0) return 'Bug\u00FCn';
'@
Add-Replace 'lib/features/contracts/services/contract_pdf_service.dart' $a $r


# ---------------------------------------------------------------------
# UYGULAMA
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '=== Baslamasina kalan sure yamasi ===' -ForegroundColor Cyan
Write-Host ('Proje koku: ' + $Root)

$state = [ordered]@{}
foreach ($p in $patches) {
    if (-not $state.Contains($p.File)) {
        $path = Join-Path $Root ($p.File.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $path)) {
            throw ('Dosya bulunamadi: ' + $path + '  (Scripti proje kokunden calistirin veya -Root verin)')
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $raw = $Utf8NoBom.GetString($bytes)
        if ($hasBom) { $raw = $raw.Substring(1) }
        $state[$p.File] = [pscustomobject]@{
            Path     = $path
            Bom      = $hasBom
            Crlf     = $raw.Contains("`r`n")
            Text     = $raw.Replace("`r`n", "`n")
            Original = $bytes
        }
    }
}

$scr = $state['lib/features/records/management_screens.dart'].Text

# On kosul: onceki yamalar uygulanmis olmali
if (-not $scr.Contains('_initialInstallments')) {
    throw 'Once onceki yamalar uygulanmalidir (yama_bedelsiz_odeme_sekli.ps1 ve sonrasi).'
}

# Bu yama daha once uygulandi mi?
if ($scr.Contains('formatDetailed(contract.startDate)')) {
    Write-Host 'ATLANDI: Bu yama zaten uygulanmis gorunuyor. Hicbir degisiklik yapilmadi.' -ForegroundColor Yellow
    return
}

$sira = 0
foreach ($p in $patches) {
    $sira++
    $s = $state[$p.File]
    $first = $s.Text.IndexOf($p.Anchor, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw ('Yama #' + $sira + ' icin aranan kod ' + $p.File + ' icinde BULUNAMADI. Dosya degismis olabilir. Hicbir dosya yazilmadi.')
    }
    $second = $s.Text.IndexOf($p.Anchor, $first + 1, [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw ('Yama #' + $sira + ' icin aranan kod ' + $p.File + ' icinde BIRDEN FAZLA yerde var. Hicbir dosya yazilmadi.')
    }
    $s.Text = $s.Text.Substring(0, $first) + $p.Text + $s.Text.Substring($first + $p.Anchor.Length)
}

foreach ($key in $state.Keys) {
    $s = $state[$key]
    $bak = $s.Path + '.bak_baslama'
    if (-not (Test-Path -LiteralPath $bak)) {
        [System.IO.File]::WriteAllBytes($bak, $s.Original)
    }
    $out = $s.Text
    if ($s.Crlf) { $out = $out.Replace("`n", "`r`n") }
    $enc = New-Object System.Text.UTF8Encoding($s.Bom)
    [System.IO.File]::WriteAllText($s.Path, $out, $enc)
    Write-Host ('YAZILDI : ' + $key) -ForegroundColor Green
}

Write-Host ''
Write-Host 'Tamamlandi. Sonraki adimlar:' -ForegroundColor Cyan
Write-Host '  1) flutter analyze'
Write-Host '  2) flutter run'
Write-Host 'Geri almak icin: her dosyanin yanindaki .bak_baslama yedegini geri kopyalayin.'
