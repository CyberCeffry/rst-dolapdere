import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../models/ad_space_model.dart';

class AdPricePdfService {
  /// [adSpaces] ekranda o an görünen (filtrelenmiş / sıralanmış) listedir.
  /// Kiracı bilgisi içermez; yalnızca fiyat listesidir.
  static Future<void> exportPrices(
    AppStore store,
    List<AdSpaceModel> adSpaces, {
    String? filterSummary,
  }) async {
    final bytes = await buildPricesPdf(
      store,
      adSpaces,
      filterSummary: filterSummary,
    );
    final fileName =
        'rst-reklam-fiyatlari-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static Future<Uint8List> buildPricesPdf(
    AppStore store,
    List<AdSpaceModel> adSpaces, {
    String? filterSummary,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final dateFormat = DateFormat('dd.MM.yyyy');
    final currency = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    final document = pw.Document(
      title: 'RST Dolapdere Reklam Fiyatları',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı fiyat listesi',
    );

    String money(double value) => value > 0 ? currency.format(value) : '-';

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
                    'RST DOLAPDERE  |  REKLAM ALANI FİYATLARI',
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
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.4),
              4: pw.FlexColumnWidth(1.4),
              5: pw.FlexColumnWidth(1.4),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Konum',
                  'Aylık + KDV',
                  '3 Aylık + KDV',
                  '6 Aylık + KDV',
                  '12 Aylık + KDV',
                ],
                boldFont,
                header: true,
              ),
              ...adSpaces.map((space) {
                final price = store.adPriceFor(space.id);
                return _row([
                  space.name,
                  space.location.trim().isEmpty ? '-' : space.location.trim(),
                  money(price?.monthly ?? 0),
                  money(price?.threeMonth ?? 0),
                  money(price?.sixMonth ?? 0),
                  money(price?.twelveMonth ?? 0),
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
  }) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.blue100)
          : null,
      children: values
          .map(
            (value) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 7,
              ),
              child: pw.Text(
                value,
                style: pw.TextStyle(font: font, fontSize: 9),
              ),
            ),
          )
          .toList(),
    );
  }
}
