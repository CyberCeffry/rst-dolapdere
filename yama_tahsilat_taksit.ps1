# =====================================================================
#  yama_tahsilat_taksit.ps1
#  - Sozlesmeye "Tahsil edildi mi" butonu (sozlesme karti + reklam alani karti)
#  - Sozlesmeye taksit secenegi: Pesin / 2 / 3 taksit (tutar otomatik bolunur)
#  - Her taksit icin "Odendi mi" isaretleme
#
#  KULLANIM (proje kokunden, ornegin rst-dolapdere klasorunde):
#     powershell -ExecutionPolicy Bypass -File .\yama_tahsilat_taksit.ps1
#
#  KODLAMA GUVENLIGI:
#   * Bu dosya SADECE ASCII karakter icerir. Turkce karakterler \uXXXX
#     olarak yazilidir ve calisirken gercek karaktere cevrilir.
#   * Dart dosyalari .NET ile UTF-8 (BOM'suz) okunur ve yazilir.
#     Get-Content / Set-Content / Out-File KULLANILMAZ.
#   * CRLF / LF durumu dosyadan okunur ve aynen korunur.
#   * Hicbir dosyaya yazmadan once tum yamalar bellekte dogrulanir.
#     Bir tanesi bile uymazsa HICBIR dosya degistirilmez.
# =====================================================================
param(
    [string]$Root = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Un([string]$s) {
    # \uXXXX dizilerini gercek karaktere cevirir; satir sonlarini LF yapar.
    $s = $s.Replace("`r`n", "`n")
    $ev = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
    }
    return [regex]::Replace($s, '\\u([0-9A-Fa-f]{4})', $ev)
}

$patches = New-Object System.Collections.ArrayList

function Add-Overwrite([string]$file, [string]$text) {
    [void]$patches.Add([pscustomobject]@{ File = $file; Mode = 'Overwrite'; Anchor = ''; Text = (Un $text) })
}
function Add-Replace([string]$file, [string]$anchor, [string]$text) {
    [void]$patches.Add([pscustomobject]@{ File = $file; Mode = 'Replace'; Anchor = (Un $anchor); Text = (Un $text) })
}

# ---------------------------------------------------------------------
# YAMA TANIMLARI
# ---------------------------------------------------------------------
$t = @'
import 'contract_history_entry.dart';  // S\u00F6zle\u015Fme ge\u00E7mi\u015Fi kay\u0131t s\u0131n\u0131f\u0131

enum ContractDurationUnit { month, year }  // S\u00F6zle\u015Fme s\u00FCresi birimi: ay veya y\u0131l

class ContractModel {  // Bir kira s\u00F6zle\u015Fmesini temsil eden veri s\u0131n\u0131f\u0131
  const ContractModel({  // Sabit yap\u0131c\u0131
    required this.id,  // S\u00F6zle\u015Fme kimli\u011Fi
    required this.customerId,  // Kirac\u0131 (m\u00FC\u015Fteri) kimli\u011Fi
    required this.adSpaceId,  // Kiralanan reklam alan\u0131n\u0131n kimli\u011Fi
    required this.startDate,  // Ba\u015Flang\u0131\u00E7 tarihi
    required this.endDate,  // Biti\u015F tarihi
    this.monthlyPrice = 0,  // Ayl\u0131k kira; varsay\u0131lan 0
    this.durationUnit = ContractDurationUnit.year,  // S\u00FCre birimi; varsay\u0131lan y\u0131l
    this.durationCount = 1,  // S\u00FCre adedi; varsay\u0131lan 1
    this.notes = '',  // Notlar; varsay\u0131lan bo\u015F
    this.isActive = true,  // Aktif mi; varsay\u0131lan evet
    this.isFinalized = false,  // Elle bitirildi mi; varsay\u0131lan hay\u0131r
    this.finalizedAt,  // Bitirilme zaman\u0131
    this.renewedFromContractId,  // Hangi s\u00F6zle\u015Fmenin yenilemesi oldu\u011Fu
    this.history = const [],  // Olay ge\u00E7mi\u015Fi; varsay\u0131lan bo\u015F liste
    this.responsibleUserId,  // Sorumlu kullan\u0131c\u0131 kimli\u011Fi
    this.responsibleUsername,  // Sorumlu kullan\u0131c\u0131 ad\u0131
    this.pdfPath,  // Ekli PDF'in g\u00F6reli yolu
    this.installmentCount = 1,  // Taksit say\u0131s\u0131: 1 = pe\u015Fin, 2 veya 3 = taksit
    this.paidInstallments = const [],  // Her taksit i\u00E7in \u00F6dendi bilgisi
  });

  final String id;  // S\u00F6zle\u015Fme kimli\u011Fi
  final String customerId;  // M\u00FC\u015Fteri ba\u011Flant\u0131s\u0131
  final String adSpaceId;  // Reklam alan\u0131 ba\u011Flant\u0131s\u0131
  final DateTime startDate;  // Ba\u015Flang\u0131\u00E7
  final DateTime endDate;  // Biti\u015F
  final double monthlyPrice;  // Ayl\u0131k bedel
  final ContractDurationUnit durationUnit;  // S\u00FCre birimi
  final int durationCount;  // S\u00FCre adedi (\u00F6r. 2 y\u0131l \u2192 2)
  final String notes;  // Serbest notlar
  final bool isActive;  // Aktif/pasif anahtar\u0131
  final bool isFinalized;  // S\u00F6zle\u015Fme sonland\u0131r\u0131ld\u0131 m\u0131
  final DateTime? finalizedAt;  // Sonland\u0131rma tarihi (bo\u015F olabilir)
  final String? renewedFromContractId;  // Yenileme zinciri i\u00E7in \u00F6nceki s\u00F6zle\u015Fme
  final List<ContractHistoryEntry> history;  // S\u00F6zle\u015Fme ge\u00E7mi\u015Fi listesi
  final String? responsibleUserId;  // Sorumlu kullan\u0131c\u0131 kimli\u011Fi
  final String? responsibleUsername;  // Sorumlu kullan\u0131c\u0131 ad\u0131

  /// S\u00F6zle\u015Fme PDF'inin 's\u00F6zle\u015Fmeler' klas\u00F6r\u00FCne g\u00F6re g\u00F6reli yolu.
  final String? pdfPath;  // PDF'in 's\u00F6zle\u015Fmeler' klas\u00F6r\u00FCne g\u00F6re yolu

  bool get hasPdf => (pdfPath ?? '').trim().isNotEmpty;  // PDF eklenmi\u015F mi? (bo\u015Fluk d\u0131\u015F\u0131nda karakter var m\u0131)

  /// Taksit say\u0131s\u0131: 1 = pe\u015Fin, 2 veya 3 = taksit.
  final int installmentCount;  // Taksit say\u0131s\u0131

  /// Her taksit i\u00E7in "\u00F6dendi mi" bilgisi (eksik kalan de\u011Ferler false say\u0131l\u0131r).
  final List<bool> paidInstallments;  // Taksit \u00F6deme durumlar\u0131

  /// Uzunlu\u011Fu her zaman taksit say\u0131s\u0131na e\u015Fit olan \u00F6deme listesi.
  List<bool> get paidFlags {
    final count = installmentCount < 1 ? 1 : installmentCount;  // En az 1 kalem
    return List<bool>.generate(
      count,
      (i) => i < paidInstallments.length && paidInstallments[i],
    );
  }

  int get paidCount => paidFlags.where((paid) => paid).length;  // \u00D6denen kalem say\u0131s\u0131

  bool get isCollected => paidCount == paidFlags.length;  // Hepsi \u00F6dendiyse tahsil edildi

  bool get hasInstallments => installmentCount > 1;  // Taksitli mi

  /// Toplam tutar\u0131n taksitlere b\u00F6l\u00FCnm\u00FC\u015F hali (kuru\u015F fark\u0131 son taksite eklenir).
  List<double> get installmentAmounts =>
      splitAmount(monthlyPrice, installmentCount);

  /// Toplam tutar\u0131 [count] e\u015Fit par\u00E7aya b\u00F6ler; kuru\u015F fark\u0131 son par\u00E7aya yaz\u0131l\u0131r.
  static List<double> splitAmount(double total, int count) {
    final n = count < 1 ? 1 : count;  // S\u0131f\u0131ra b\u00F6lmeyi engelle
    final cents = (total * 100).round();  // Kuru\u015F cinsinden tamsay\u0131
    final base = cents ~/ n;  // Her par\u00E7an\u0131n kuru\u015Fu
    final remainder = cents - base * n;  // Kalan kuru\u015F
    return List<double>.generate(
      n,
      (i) => (i == n - 1 ? base + remainder : base) / 100,
    );
  }

  /// "Pe\u015Fin" veya "2 taksit" gibi k\u0131sa etiket.
  String get paymentMethodLabel =>
      installmentCount <= 1 ? 'Pe\u015Fin' : '$installmentCount taksit';

  /// Kartlarda g\u00F6sterilen tahsilat \u00F6zeti.
  String get paymentSummary {
    if (installmentCount <= 1) {
      return isCollected ? 'Pe\u015Fin \u2022 Tahsil edildi' : 'Pe\u015Fin \u2022 Tahsil edilmedi';
    }
    if (isCollected) return '$installmentCount taksit \u2022 Tahsil edildi';
    return '$installmentCount taksit \u2022 $paidCount/$installmentCount \u00F6dendi';
  }

  factory ContractModel.fromJson(Map<String, dynamic> json) => ContractModel(  // JSON'dan s\u00F6zle\u015Fme \u00FCretir
    id: json['id'] as String,  // Kimlik zorunlu
    customerId: json['customerId'] as String? ?? '',  // M\u00FC\u015Fteri kimli\u011Fi yoksa bo\u015F
    adSpaceId: json['adSpaceId'] as String? ?? '',  // Alan kimli\u011Fi yoksa bo\u015F
    startDate:  // Ba\u015Flang\u0131\u00E7 tarihi
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now(),  // Metni tarihe \u00E7evir; olmazsa \u015Fimdi
    endDate:  // Biti\u015F tarihi
        DateTime.tryParse(json['endDate'] as String? ?? '') ?? DateTime.now(),  // Metni tarihe \u00E7evir; olmazsa \u015Fimdi
    monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,  // Fiyat\u0131 double yap; yoksa 0
    durationUnit: ContractDurationUnit.values.firstWhere(  // Metin olarak saklanan birimi enum'a \u00E7evir
      (unit) => unit.name == json['durationUnit'],  // Ad\u0131 e\u015Fle\u015Fen birimi bul
      orElse: () => ContractDurationUnit.year,  // Bulunamazsa y\u0131l kabul et
    ),
    durationCount: (json['durationCount'] as num?)?.toInt() ?? 1,  // S\u00FCre adedini tamsay\u0131 yap; yoksa 1
    notes: json['notes'] as String? ?? '',  // Not yoksa bo\u015F
    isActive: json['isActive'] as bool? ?? true,  // De\u011Fer yoksa aktif
    isFinalized: json['isFinalized'] as bool? ?? false,  // De\u011Fer yoksa bitirilmemi\u015F
    finalizedAt: DateTime.tryParse(json['finalizedAt'] as String? ?? ''),  // Bitirilme tarihini \u00E7evir
    renewedFromContractId: json['renewedFromContractId'] as String?,  // Yenileme kayna\u011F\u0131n\u0131 oku
    responsibleUserId: json['responsibleUserId'] as String?,  // Sorumlu kimli\u011Fini oku
    responsibleUsername: json['responsibleUsername'] as String?,  // Sorumlu ad\u0131n\u0131 oku
    pdfPath: json['pdfPath'] as String?,  // PDF yolunu oku
    installmentCount:  // Taksit say\u0131s\u0131 (eski kay\u0131tlarda yok = pe\u015Fin)
        ((json['installmentCount'] as num?)?.toInt() ?? 1).clamp(1, 12).toInt(),
    paidInstallments:  // Taksit \u00F6deme durumlar\u0131
        (json['paidInstallments'] as List<dynamic>? ?? const [])
            .map((item) => item == true)
            .toList(),
    history: (json['history'] as List<dynamic>? ?? const [])  // Ge\u00E7mi\u015F listesini al; yoksa bo\u015F liste
        .map(  // Her \u00F6\u011Feyi d\u00F6n\u00FC\u015Ft\u00FCr
          (entry) => ContractHistoryEntry.fromJson(  // Her \u00F6\u011Feden ge\u00E7mi\u015F kayd\u0131 \u00FCret
            Map<String, dynamic>.from(entry as Map),  // \u00D6\u011Feyi tipli haritaya \u00E7evir
          ),
        )
        .toList(),  // Sonucu listeye topla
  );

  Map<String, dynamic> toJson() => {  // S\u00F6zle\u015Fmeyi JSON haritas\u0131na \u00E7evirir
    'id': id,  // Kimlik
    'customerId': customerId,  // M\u00FC\u015Fteri kimli\u011Fi
    'adSpaceId': adSpaceId,  // Alan kimli\u011Fi
    'startDate': startDate.toIso8601String(),  // Ba\u015Flang\u0131\u00E7 (ISO metin)
    'endDate': endDate.toIso8601String(),  // Biti\u015F (ISO metin)
    'monthlyPrice': monthlyPrice,  // Ayl\u0131k bedel
    'durationUnit': durationUnit.name,  // Birim ad\u0131 (metin)
    'durationCount': durationCount,  // S\u00FCre adedi
    'notes': notes,  // Notlar
    'isActive': isActive,  // Aktiflik
    'isFinalized': isFinalized,  // Sonland\u0131r\u0131ld\u0131 m\u0131
    'finalizedAt': finalizedAt?.toIso8601String(),  // Sonland\u0131rma tarihi (varsa)
    'renewedFromContractId': renewedFromContractId,  // Yenileme kayna\u011F\u0131
    'responsibleUserId': responsibleUserId,  // Sorumlu kimli\u011Fi
    'responsibleUsername': responsibleUsername,  // Sorumlu ad\u0131
    'pdfPath': pdfPath,  // PDF yolu
    'installmentCount': installmentCount,  // Taksit say\u0131s\u0131
    'paidInstallments': paidInstallments,  // Taksit \u00F6deme durumlar\u0131
    'history': history.map((entry) => entry.toJson()).toList(),  // Ge\u00E7mi\u015F kay\u0131tlar\u0131n\u0131 JSON listesine \u00E7evir
  };
}

'@
Add-Overwrite 'lib/models/contract_model.dart' $t

$a = @'
pdfPath: contract.pdfPath,
'@
$r = @'
pdfPath: contract.pdfPath,
      installmentCount: contract.installmentCount,
      paidInstallments: contract.paidInstallments,
'@
Add-Replace 'lib/core/services/app_store.dart' $a $r

$a = @'
pdfPath: renewed.pdfPath,
'@
$r = @'
pdfPath: renewed.pdfPath,
      installmentCount: renewed.installmentCount,
      paidInstallments: renewed.paidInstallments,
'@
Add-Replace 'lib/core/services/app_store.dart' $a $r

$a = @'
    String? pdfPath,
  }) {
    return ContractModel(
'@
$r = @'
    String? pdfPath,
    int? installmentCount,
    List<bool>? paidInstallments,
  }) {
    return ContractModel(
'@
Add-Replace 'lib/core/services/app_store.dart' $a $r

$a = @'
pdfPath: pdfPath ?? source.pdfPath,
'@
$r = @'
pdfPath: pdfPath ?? source.pdfPath,
      installmentCount: installmentCount ?? source.installmentCount,
      paidInstallments: paidInstallments ?? source.paidInstallments,
'@
Add-Replace 'lib/core/services/app_store.dart' $a $r

$a = @'
  // S\u00F6zle\u015Fmeyi aktif/pasif yapar ve ge\u00E7mi\u015Fe kaydeder.

'@
$r = @'
  // S\u00F6zle\u015Fmenin taksit / tahsilat (\u00F6dendi mi) durumunu g\u00FCnceller.
  Future<void> setContractPayments(String id, List<bool> paid) async {
    final index = _contracts.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('S\u00F6zle\u015Fme bulunamad\u0131.');
    final updated = _copyContract(
      _contracts[index],
      paidInstallments: List<bool>.from(paid),
    );
    _contracts[index] = updated;
    await _persistCollection('contracts', [updated]);
    notifyListeners();
  }

  // S\u00F6zle\u015Fmeyi aktif/pasif yapar ve ge\u00E7mi\u015Fe kaydeder.

'@
Add-Replace 'lib/core/services/app_store.dart' $a $r

$a = @'
        if (record.hasPdf)
          const SpaceMenuItem(
            value: 'pdf',
'@
$r = @'
        const SpaceMenuItem(
          value: 'payment',
          label: 'Tahsilat / taksit durumu',
          icon: Icons.payments_outlined,
        ),
        if (record.hasPdf)
          const SpaceMenuItem(
            value: 'pdf',
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
                        case 'pdf':
                          _openContractPdf(record);
'@
$r = @'
                        case 'payment':
                          _showPaymentDialog(record);
                        case 'pdf':
                          _openContractPdf(record);
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
      icon = Icons.description_outlined;
'@
$r = @'
      icon = Icons.description_outlined;
      subtitleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          const SizedBox(height: 6),
          _paymentButton(contract),
        ],
      );
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
  Widget _recordTile(dynamic record) {
'@
$r = @'
  Color _paymentColor(ContractModel contract) {
    if (contract.isCollected) return AppColors.success;
    if (contract.paidCount > 0) return AppColors.warning;
    return AppColors.danger;
  }

  Widget _paymentButton(ContractModel contract) {
    final color = _paymentColor(contract);
    return OutlinedButton.icon(
      onPressed: () => _showPaymentDialog(contract),
      icon: Icon(
        contract.isCollected ? Icons.check_circle : Icons.payments_outlined,
        size: 16,
        color: color,
      ),
      label: Text(
        contract.paymentSummary,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }

  Future<void> _showPaymentDialog(ContractModel contract) async {
    final result = await showDialog<List<bool>>(
      context: context,
      builder: (_) => _PaymentDialog(contract: contract),
    );
    if (result == null || !mounted) return;
    try {
      await widget.store.setContractPayments(contract.id, result);
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Widget _recordTile(dynamic record) {
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
                    'Tutar: ${NumberFormat.currency(locale: 'tr_TR', symbol: '\u20BA').format(contract.monthlyPrice)}\n',
              ),
              const TextSpan(text: 'Kalan s\u00FCre: '),
'@
$r = @'
                    'Tutar: ${NumberFormat.currency(locale: 'tr_TR', symbol: '\u20BA').format(contract.monthlyPrice)}\n',
              ),
              TextSpan(
                text: '\u00D6deme: ${contract.paymentSummary}\n',
                style: TextStyle(
                  color: _paymentColor(contract),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const TextSpan(text: 'Kalan s\u00FCre: '),
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
              if (contract.notes.isNotEmpty) Text('Notlar: ${contract.notes}'),
'@
$r = @'
              Text('\u00D6deme \u015Fekli: ${contract.paymentMethodLabel}'),
              Text('Tahsilat: ${contract.paymentSummary}'),
              if (contract.hasInstallments)
                for (var i = 0; i < contract.installmentCount; i++)
                  Text(
                    '  ${i + 1}. taksit: '
                    '${currencyFormat.format(contract.installmentAmounts[i])}'
                    ' \u2022 ${contract.paidFlags[i] ? '\u00D6dendi' : '\u00D6denmedi'}',
                  ),
              if (contract.notes.isNotEmpty) Text('Notlar: ${contract.notes}'),
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
  late bool _active;
'@
$r = @'
  late bool _active;
  int _installments = 1;
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
    _existingPdf = initial is ContractModel ? initial.pdfPath : null;
'@
$r = @'
    _existingPdf = initial is ContractModel ? initial.pdfPath : null;
    _installments = initial is ContractModel ? initial.installmentCount : 1;
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
  double _parsePrice() =>
      double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0;
'@
$r = @'
  double _parsePrice() =>
      double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? 0;

  /// Kay\u0131tta saklanacak taksit \u00F6deme durumlar\u0131. D\u00FCzenlemede taksit say\u0131s\u0131
  /// de\u011Fi\u015Fmediyse eski i\u015Faretler korunur; yenilemede veya say\u0131 de\u011Fi\u015Fince s\u0131f\u0131rlan\u0131r.
  List<bool> _paymentFlagsForSave() {
    final initial = widget.initial;
    if (!widget.isRenewal &&
        initial is ContractModel &&
        initial.installmentCount == _installments) {
      return List<bool>.from(initial.paidFlags);
    }
    return List<bool>.filled(_installments, false);
  }

  Widget _installmentPreview() {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '\u20BA');
    final total = _parsePrice();
    final amounts = ContractModel.splitAmount(total, _installments);
    if (_installments <= 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('Pe\u015Fin \u00F6deme: ${money.format(total)}'),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < amounts.length; i++)
            Text('${i + 1}. taksit: ${money.format(amounts[i])}'),
        ],
      ),
    );
  }
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
                  _textField('Notlar', _notes, maxLines: 3),
                  // if (ContractFileService.isSupported) _pdfSection(),
'@
$r = @'
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '\u00D6deme \u015Fekli',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Pe\u015Fin')),
                      ButtonSegment(value: 2, label: Text('2 Taksit')),
                      ButtonSegment(value: 3, label: Text('3 Taksit')),
                    ],
                    selected: {_installments},
                    onSelectionChanged: (selection) =>
                        setState(() => _installments = selection.first),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _price,
                    builder: (context, value, child) => _installmentPreview(),
                  ),
                  const SizedBox(height: 12),
                  _textField('Notlar', _notes, maxLines: 3),
                  // if (ContractFileService.isSupported) _pdfSection(),
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
          pdfPath: pdfPlan.relativePath,
'@
$r = @'
          pdfPath: pdfPlan.relativePath,
          installmentCount: _installments,
          paidInstallments: _paymentFlagsForSave(),
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r

$a = @'
class _DatePartsField extends StatefulWidget {
'@
$r = @'
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.contract});

  final ContractModel contract;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late List<bool> _paid;

  @override
  void initState() {
    super.initState();
    _paid = List<bool>.from(widget.contract.paidFlags);
  }

  @override
  Widget build(BuildContext context) {
    final contract = widget.contract;
    final amounts = contract.installmentAmounts;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '\u20BA');
    final single = contract.installmentCount <= 1;
    return AlertDialog(
      title: Text(single ? 'Tahsilat durumu' : 'Taksit \u00F6demeleri'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Toplam tutar: ${money.format(contract.monthlyPrice)}'),
            const SizedBox(height: 8),
            for (var i = 0; i < _paid.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _paid[i],
                onChanged: (value) =>
                    setState(() => _paid[i] = value ?? false),
                title: Text(
                  single
                      ? 'Pe\u015Fin \u00F6deme \u2022 ${money.format(amounts[i])}'
                      : '${i + 1}. taksit \u2022 ${money.format(amounts[i])}',
                ),
                subtitle: Text(
                  single
                      ? (_paid[i] ? 'Tahsil edildi' : 'Tahsil edilmedi')
                      : (_paid[i] ? '\u00D6dendi' : '\u00D6denmedi'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazge\u00E7'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _paid),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _DatePartsField extends StatefulWidget {
'@
Add-Replace 'lib/features/records/management_screens.dart' $a $r


# ---------------------------------------------------------------------
# UYGULAMA
# ---------------------------------------------------------------------
Write-Host ''
Write-Host '=== Tahsilat / Taksit yamasi ===' -ForegroundColor Cyan
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

# Daha once uygulandi mi?
foreach ($key in @($state.Keys)) {
    if ($state[$key].Text.Contains('setContractPayments') -or $state[$key].Text.Contains('installmentCount')) {
        Write-Host ('ATLANDI: ' + $key + ' dosyasinda yama zaten var gorunuyor. Hicbir degisiklik yapilmadi.') -ForegroundColor Yellow
        return
    }
}

$sira = 0
foreach ($p in $patches) {
    $sira++
    $s = $state[$p.File]
    if ($p.Mode -eq 'Overwrite') {
        $s.Text = $p.Text.TrimEnd("`n") + "`n"
        continue
    }
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

# Yedek al + yaz
foreach ($key in $state.Keys) {
    $s = $state[$key]
    $bak = $s.Path + '.bak_tahsilat'
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
Write-Host 'Geri almak icin: her dosyanin yanindaki .bak_tahsilat yedegini geri kopyalayin.'
