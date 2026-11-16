import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
// import 'package:printing/printing.dart';

import '../../../core/services/app_store.dart';
import '../../../models/contract_model.dart';
import 'dart:io';

class ContractPdfService {
  static Future<void> exportContracts(
    AppStore store,
    List<ContractModel> contracts,
  ) async {
    final bytes = await buildContractsPdf(store, contracts);
    final fileName =
        'rst-sozlesmeleri-${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
    // await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
  }

  static Future<Uint8List> buildContractsPdf(
    AppStore store,
    List<ContractModel> contracts,
  ) async {
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
    final sorted = [...contracts]
      ..sort((a, b) => a.endDate.compareTo(b.endDate));

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'RST DOLAPDERE  |  SÖZLEŞMELER',
                style: pw.TextStyle(font: boldFont, fontSize: 16),
              ),
              pw.Text('Dışa aktarma: ${dateFormat.format(DateTime.now())}'),
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
              0: pw.FlexColumnWidth(1.7),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.3),
              4: pw.FlexColumnWidth(1.4),
              5: pw.FlexColumnWidth(1.3),
              6: pw.FlexColumnWidth(1.1),
              7: pw.FlexColumnWidth(1.2),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Kiracı',
                  'Başlangıç',
                  'Bitiş',
                  'Bedel',
                  'Durum',
                  'Süre',
                  'Sorumlu',
                ],
                boldFont,
                header: true,
              ),
              ...sorted.map((contract) {
                final customer = store.customerFor(contract.customerId);
                final space = store.adSpaceFor(contract.adSpaceId);
                final status = contract.isFinalized
                    ? 'Bitti olarak işaretlendi'
                    : contract.endDate.isBefore(DateTime.now())
                    ? 'Süresi doldu'
                    : 'Aktif';
                final durationUnit =
                    contract.durationUnit == ContractDurationUnit.month
                    ? 'ay'
                    : 'yıl';
                return _row([
                  space?.name ?? 'Reklam alanı',
                  customer?.name ?? 'Müşteri',
                  dateFormat.format(contract.startDate),
                  dateFormat.format(contract.endDate),
                  currencyFormat.format(contract.monthlyPrice),
                  status,
                  '${contract.durationCount} $durationUnit',
                  contract.responsibleUsername ?? '-',
                ], font);
              }),
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
  }) => pw.TableRow(
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey200)
        : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8)),
          ),
        )
        .toList(),
  );
}
