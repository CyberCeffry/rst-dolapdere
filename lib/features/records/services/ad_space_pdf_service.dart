import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/services/app_store.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../models/ad_space_model.dart';

class AdSpacePdfService {
  static Future<void> exportAdSpaces(
    AppStore store,
    List<AdSpaceModel> adSpaces,
  ) async {
    final bytes = await buildAdSpacesPdf(store, adSpaces);
    await Printing.layoutPdf(
      name:
          'rst-reklam-alanlari-${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  static Future<Uint8List> buildAdSpacesPdf(
    AppStore store,
    List<AdSpaceModel> adSpaces,
  ) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final dateFormat = DateFormat('dd.MM.yyyy');
    final document = pw.Document(
      title: 'RST Dolapdere Reklam Alanları',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı ve kiracı durumu',
    );
    final sorted = [...adSpaces]..sort((a, b) => a.name.compareTo(b.name));

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
                'RST DOLAPDERE  |  REKLAM ALANLARI',
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
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(1.5),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Kiracı',
                  'Bitiş tarihi',
                  'Kalan süre',
                  'Durum',
                  'Sorumlu',
                ],
                boldFont,
                header: true,
              ),
              ...sorted.map((space) {
                final contract = store.activeContractForAdSpace(space.id);
                final customer = contract == null
                    ? null
                    : store.customerFor(contract.customerId);
                final days = contract == null
                    ? null
                    : ContractRemainingTime.daysUntil(contract.endDate);
                return _row(
                  [
                    space.name,
                    customer?.name ?? 'Kiracı yok',
                    contract == null
                        ? '-'
                        : dateFormat.format(contract.endDate),
                    days == null ? '-' : ContractRemainingTime.format(days),
                    contract == null ? 'Boş' : 'Kirada',
                    contract?.responsibleUsername ?? '-',
                  ],
                  font,
                  remainingColor:
                      days != null && ContractRemainingTime.isUrgent(days)
                      ? PdfColors.red
                      : null,
                );
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
    PdfColor? remainingColor,
  }) => pw.TableRow(
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey200)
        : null,
    children: values.indexed
        .map(
          (entry) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: pw.Text(
              entry.$2,
              style: pw.TextStyle(
                font: font,
                fontSize: 8,
                color: entry.$1 == 3 ? remainingColor : null,
              ),
            ),
          ),
        )
        .toList(),
  );
}
