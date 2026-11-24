import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/app_store.dart';
import '../../../core/utils/contract_remaining_time.dart';
import '../../../models/ad_space_model.dart';
import '../../../models/contract_model.dart';

class AdSpacePdfService {
  /// [adSpaces] ekranda o an görünen (filtrelenmiş ve sıralanmış) listedir.
  /// PDF bu sırayı aynen kullanır; ayrıca yeniden sıralama yapılmaz.
  /// [filterSummary] verilirse başlığın altında "Filtre: ..." satırı olarak yazılır.
  static Future<void> exportAdSpaces(
    AppStore store,
    List<AdSpaceModel> adSpaces, {
    String? filterSummary,
  }) async {
    final bytes = await buildAdSpacesPdf(
      store,
      adSpaces,
      filterSummary: filterSummary,
    );

    final fileName =
        'rst-reklam-alanlari-${DateTime.now().millisecondsSinceEpoch}.pdf';

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
    );

    await file.writeAsBytes(bytes, flush: true);

    await Process.run('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }

  static Future<Uint8List> buildAdSpacesPdf(
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

    final document = pw.Document(
      title: 'RST Dolapdere Reklam Alanları',
      author: 'RST Dolapdere',
      subject: 'Reklam alanı ve kiracı durumu',
    );

    // Sıralama ekrandan gelir; burada değiştirilmez.
    final ordered = [...adSpaces];

    // Toplam reklam alanı.
    final totalAdSpaces = ordered.length;

    // Aktif sözleşmesi bulunan reklam alanları.
    // Aynı kiracı birden fazla alanda olsa da her alan ayrı sayılır.
    final occupiedAdSpaces = ordered.where((space) {
      return store.activeContractForAdSpace(space.id) != null;
    }).length;

    // Aktif sözleşmesi bulunmayan reklam alanları.
    final emptyAdSpaces = totalAdSpaces - occupiedAdSpaces;

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
                    'RST DOLAPDERE  |  REKLAM ALANLARI',
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
              6: pw.FlexColumnWidth(2.4),
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(1.4),
            },

            children: [
              // Tablo başlığı.
              _row(
                const [
                  'Reklam alanı',
                  'Kiracı',
                  'Bitiş tarihi',
                  'Kalan süre',
                  'Durum',
                  'Rezerve',
                  'Açıklama',
                ],
                boldFont,
                header: true,
              ),

              // Reklam alanları (ekrandaki sırayla).
              ...ordered.map((space) {
                final contract = store.activeContractForAdSpace(space.id);

                final customer = contract == null
                    ? null
                    : store.customerFor(contract.customerId);

                final days = contract == null
                    ? null
                    : ContractRemainingTime.daysUntil(contract.endDate);

                final isEmpty = contract == null;

                return _row(
                  [
                    space.name,
                    customer?.name ?? 'Kiracı yok',
                    contract == null
                        ? '-'
                        : dateFormat.format(contract.endDate),
                    contract == null
                        ? '-'
                        : ContractRemainingTime.formatDetailed(
                            contract.endDate,
                          ),
                    isEmpty
                        ? (store.reservedByNameFor(space.id) != null
                              ? 'Rezerve'
                              : 'Boş')
                        : 'Kirada',
                    store.reservedByNameFor(space.id) ?? '-',
                    _notesFor(store, space, contract),
                  ],
                  font,

                  // Sözleşmesi olmayan satırların arka planı sarı.
                  empty: isEmpty,

                  // Acil sözleşmelerin kalan süre yazısı kırmızı.
                  remainingColor:
                      days != null && ContractRemainingTime.isUrgent(days)
                      ? PdfColors.red
                      : null,
                );
              }),

              // Toplam reklam alanı, dolu ve boş alan özeti.
              _row(
                [
                  'TOPLAM $totalAdSpaces ALAN',
                  'TOPLAM $occupiedAdSpaces DOLU',
                  '',
                  '',
                  'TOPLAM $emptyAdSpaces BOŞ',
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

  /// Duruma özel not: kirada ise sözleşme notu, rezerve ise rezervasyon notu;
  /// ikisi de yoksa reklam alanı açıklaması.
  static String _notesFor(
    AppStore store,
    AdSpaceModel space,
    ContractModel? contract,
  ) {
    final parts = <String>[];
    final contractNote = contract?.notes.trim() ?? '';
    if (contractNote.isNotEmpty) parts.add(contractNote);
    final reservationNote =
        store.reservationForAdSpace(space.id)?.notes.trim() ?? '';
    if (reservationNote.isNotEmpty) {
      parts.add(
        contract == null ? reservationNote : 'Rezervasyon: $reservationNote',
      );
    }
    if (parts.isEmpty) {
      final description = space.description.trim();
      return description.isEmpty ? '-' : description;
    }
    return parts.join('\n');
  }

  static pw.TableRow _row(
    List<String> values,
    pw.Font font, {
    bool header = false,
    bool empty = false,
    bool total = false,
    PdfColor? remainingColor,
  }) {
    return pw.TableRow(
      decoration: header || total
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

              // Başlık ve toplam satırları kalın.
              fontWeight: header || total
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,

              // Yalnızca kalan süre sütununun rengi değişir.
              color: entry.$1 == 3 ? remainingColor : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}
