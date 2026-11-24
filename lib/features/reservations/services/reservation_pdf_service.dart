import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../models/reservation_model.dart';

class ReservationPdfService {
  /// [reservations] ekranda o an görünen (filtrelenmiş / sıralanmış) listedir;
  /// PDF bu sırayı aynen kullanır.
  static Future<void> exportReservations(
    AppStore store,
    List<ReservationModel> reservations, {
    String? filterSummary,
  }) async {
    final bytes = await buildReservationsPdf(
      store,
      reservations,
      filterSummary: filterSummary,
    );
    final fileName =
        'rst-rezervasyonlar-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.pdf';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static Future<Uint8List> buildReservationsPdf(
    AppStore store,
    List<ReservationModel> reservations, {
    String? filterSummary,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSans-Variable.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);
    final dateFormat = DateFormat('dd.MM.yyyy');
    final currencyFormat = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    final document = pw.Document(
      title: 'RST Dolapdere Rezervasyonlar',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı rezervasyonları',
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
                    'RST DOLAPDERE  |  REZERVASYONLAR',
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
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(1.5),
              4: pw.FlexColumnWidth(1.5),
              5: pw.FlexColumnWidth(2.4),
            },
            children: [
              _row(
                const [
                  'Reklam alanı',
                  'Rezerve eden',
                  'Mevcut kiracı',
                  'Kalan süre',
                  'Verilen tutar',
                  'Açıklama',
                ],
                boldFont,
                header: true,
              ),
              ...reservations.map((reservation) {
                final space = store.adSpaceFor(reservation.adSpaceId);
                final reserver = store.customerFor(reservation.customerId);
                final contract = store.activeContractForAdSpace(
                  reservation.adSpaceId,
                );
                final tenant = contract == null
                    ? null
                    : store.customerFor(contract.customerId);
                final isEmpty = contract == null;
                final days = contract == null
                    ? null
                    : ContractRemainingTime.daysUntil(contract.endDate);
                return _row(
                  [
                    space?.name ?? 'Reklam alanı',
                    reserver?.name ?? 'Müşteri',
                    isEmpty ? 'Kiracı yok' : (tenant?.name ?? 'Bilinmiyor'),
                    contract == null
                        ? '-'
                        : ContractRemainingTime.formatDetailed(
                            contract.endDate,
                          ),
                    contract == null
                        ? '-'
                        : currencyFormat.format(contract.monthlyPrice),
                    reservation.notes.trim().isEmpty
                        ? '-'
                        : reservation.notes.trim(),
                  ],
                  font,
                  empty: isEmpty,
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
    bool empty = false,
    PdfColor? remainingColor,
  }) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.grey200)
          : empty
          ? const pw.BoxDecoration(color: PdfColors.yellow100)
          : null,
      children: values.indexed.map((entry) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: pw.Text(
            entry.$2,
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: entry.$1 == 3 ? remainingColor : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}