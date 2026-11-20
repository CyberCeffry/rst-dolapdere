import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../core/utils/date_helper.dart';
import '../../../models/contract_model.dart';

class ContractPdfService {
  /// [contracts] ekranda o an görünen (filtrelenmiş / sıralanmış) listedir.
  static Future<void> exportContracts(
    AppStore store,
    List<ContractModel> contracts, {
    String? filterSummary,
  }) async {
    final bytes = await buildContractsPdf(
      store,
      contracts,
      filterSummary: filterSummary,
    );
    final fileName =
        'rst-sozlesmeleri-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static String _status(ContractModel contract) {
    final days = DateHelper.daysUntil(contract.endDate);
    if (contract.isFinalized) return 'Bitti';
    if (days < 0) return 'Süresi doldu';
    if (!contract.isActive) return 'Pasif';
    if (DateHelper.daysUntil(contract.startDate) > 0) return 'Başlayacak';
    return 'Aktif';
  }

  static String _remaining(ContractModel contract) {
    if (contract.isFinalized) return '-';
    final days = DateHelper.daysUntil(contract.endDate);
    if (days < 0) return '-';
    if (days == 0) return 'Bugün';
    return ContractRemainingTime.format(days);
  }

  static Future<Uint8List> buildContractsPdf(
    AppStore store,
    List<ContractModel> contracts, {
    String? filterSummary,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final document = pw.Document(
      title: 'RST Dolapdere Sözleşme Listesi',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı sözleşmeleri',
    );
    final dateFormat = DateFormat('dd.MM.yyyy');
    final currencyFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final total = contracts.fold<double>(
      0,
      (sum, contract) => sum + contract.monthlyPrice,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'RST DOLAPDERE  |  SÖZLEŞMELER',
                    style: pw.TextStyle(font: boldFont, fontSize: 16),
                  ),
                  pw.Text('Dışa aktarma: ${dateFormat.format(DateTime.now())}'),
                ],
              ),
              if (filterSummary != null && filterSummary.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(
                    'Filtre: $filterSummary',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${context.pageNumber} / ${context.pagesCount}'),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(1.8),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(1.3),
              6: pw.FlexColumnWidth(1.3),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Kiracı',
                  'Bitiş',
                  'Süre',
                  'Kalan süre',
                  'Bedel + KDV',
                  'Durum',
                ],
                boldFont,
                header: true,
              ),
              ...contracts.map((contract) {
                final customer = store.customerFor(contract.customerId);
                final space = store.adSpaceFor(contract.adSpaceId);
                final unit = contract.durationUnit == ContractDurationUnit.month
                    ? 'ay'
                    : 'yıl';
                return _row([
                  space?.name ?? 'Reklam alanı',
                  customer?.name ?? 'Müşteri',
                  dateFormat.format(contract.endDate),
                  '${contract.durationCount} $unit',
                  _remaining(contract),
                  currencyFormat.format(contract.monthlyPrice),
                  _status(contract),
                ], font);
              }),
              _row(
                [
                  'TOPLAM (${contracts.length} sözleşme)',
                  '',
                  '',
                  '',
                  '',
                  '${currencyFormat.format(total)} + KDV',
                  '',
                ],
                boldFont,
                total: true,
              ),
            ],
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.TableRow _row(
    List<String> values,
    pw.Font font, {
    bool header = false,
    bool total = false,
  }) => pw.TableRow(
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey200)
        : total
        ? const pw.BoxDecoration(color: PdfColors.grey100)
        : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: font,
                fontSize: total ? 9 : 8,
                fontWeight: total ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(),
  );
}
