# =====================================================================
#  yama_taksit5_pdf_son_odeme.ps1   (5. yama)
#  - Sozlesme formunda taksit secenekleri: Pesin / 2 / 3 / 4 / 5 Taksit / Bedelsiz
#  - Sozlesme PDF'inde "Odeme durumu" sutununda EN SON ODENEN TAKSIT yazilir
#    (ornek: "3. taksit odendi"; hepsi bitmisse "5. taksit odendi (tamamlandi)")
#
#  ON KOSUL: yama_bedelsiz_odeme_sekli.ps1 uygulanmis olmali.
#
#  KULLANIM (proje kokunden):
#     powershell -ExecutionPolicy Bypass -File .\yama_taksit5_pdf_son_odeme.ps1
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
  $ev = [System.Text.RegularExpressions.MatchEvaluator] {
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
  bool get isAllFree => freeCount == paidFlags.length;  // Hepsi bedelsiz mi

'@
$r = @'
  bool get isAllFree => freeCount == paidFlags.length;  // Hepsi bedelsiz mi

  /// En son \u00F6denen taksit numaras\u0131 (1'den ba\u015Flar); hi\u00E7 \u00F6deme yoksa 0.
  int get lastPaidInstallment {
    final states = paymentStates;
    for (var i = states.length - 1; i >= 0; i--) {
      if (states[i] == 1) return i + 1;
    }
    return 0;
  }

'@
Add-Replace 'lib/models/contract_model.dart' $a $r

$a = @'
  /// Taksit say\u0131s\u0131ndan ba\u011F\u0131ms\u0131z: tamam\u0131 \u00F6dendiyse (veya bedelsizse) '\u00D6dendi'.
  static String _paymentStatus(ContractModel contract) {
    if (contract.isAllFree) return 'Bedelsiz';
    return contract.isCollected ? '\u00D6dendi' : '\u00D6denmedi';
  }
'@
$r = @'
  /// Pe\u015Finse \u00D6dendi/\u00D6denmedi; taksitliyse en son \u00F6denen taksit yaz\u0131l\u0131r.
  static String _paymentStatus(ContractModel contract) {
    if (contract.isAllFree) return 'Bedelsiz';
    if (!contract.hasInstallments) {
      return contract.isCollected ? '\u00D6dendi' : '\u00D6denmedi';
    }
    final last = contract.lastPaidInstallment;
    if (last == 0) return '\u00D6denmedi';
    final done = contract.isCollected ? ' (tamamland\u0131)' : '';
    return '$last. taksit \u00F6dendi$done';
  }
'@
Add-Replace 'lib/features/contracts/services/contract_pdf_service.dart' $a $r

$a = @'
              6: pw.FlexColumnWidth(1.1),
              7: pw.FlexColumnWidth(1.5),
'@
$r = @'
              6: pw.FlexColumnWidth(1.5),
              7: pw.FlexColumnWidth(1.3),
'@
Add-Replace 'lib/features/contracts/services/contract_pdf_service.dart' $a $r

$a = @'
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Pe\u015Fin')),
                      ButtonSegment(value: 2, label: Text('2 Taksit')),
                      ButtonSegment(value: 3, label: Text('3 Taksit')),
                      ButtonSegment(value: 0, label: Text('Bedelsiz')),
                    ],
                    selected: {_installments},
                    onSelectionChanged: (selection) =>
                        setState(() => _installments = selection.first),
                  ),
'@
$r = @'
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('Pe\u015Fin')),
                        ButtonSegment(value: 2, label: Text('2 Taksit')),
                        ButtonSegment(value: 3, label: Text('3 Taksit')),
                        ButtonSegment(value: 4, label: Text('4 Taksit')),
                        ButtonSegment(value: 5, label: Text('5 Taksit')),
                        ButtonSegment(value: 0, label: Text('Bedelsiz')),
                      ],
                      selected: {_installments},
                      onSelectionChanged: (selection) =>
                          setState(() => _installments = selection.first),
                    ),
                  ),
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r


# ---------------------------------------------------------------------
# UYGULAMA
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '=== Taksit 5 / PDF son odeme yamasi ===' -ForegroundColor Cyan
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
$mdl = $state['lib/models/contract_model.dart'].Text

# On kosul: onceki yamalar uygulanmis olmali
if (-not $scr.Contains('_initialInstallments') -or -not $mdl.Contains('freeInstallments')) {
  throw 'Once onceki yamalar uygulanmalidir (yama_bedelsiz_odeme_sekli.ps1 dahil).'
}

# Bu yama daha once uygulandi mi?
if ($mdl.Contains('lastPaidInstallment')) {
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
  $bak = $s.Path + '.bak_taksit5'
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
Write-Host 'Geri almak icin: her dosyanin yanindaki .bak_taksit5 yedegini geri kopyalayin.'
