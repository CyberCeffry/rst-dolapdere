import '../../models/contract_model.dart'; // ContractDurationUnit enum'u için

class ContractDateHelper {
  // Sözleşme tarihi hesaplayan yardımcı (nesne üretilmez, static)
  static DateTime addDuration(
    // Başlangıca ay/yıl ekleyip bitiş tarihini hesaplar
    DateTime startDate, { // Başlangıç tarihi
    required ContractDurationUnit unit, // Birim: ay veya yıl
    required int count, // Kaç birim eklenecek
  }) {
    // Metot gövdesi başlar
    if (count < 1) {
      // Süre 1'den küçükse geçersiz
      throw ArgumentError.value(
        count,
        'count',
        'Süre en az 1 olmalıdır.',
      ); // Hata fırlatıp işlemi durdur
    }

    final totalMonths = unit == ContractDurationUnit.year
        ? count * 12
        : count; // Her şeyi aya çevir (yıl × 12)
    final targetMonthIndex =
        startDate.month - 1 + totalMonths; // 0 tabanlı hedef ay sırası (Ocak=0)
    final targetYear =
        startDate.year +
        targetMonthIndex ~/ 12; // Taşan ayları yıla ekle (tamsayı bölme)
    final targetMonth = targetMonthIndex % 12 + 1; // Yıl içindeki ay (1-12)
    final lastDay = DateTime(
      targetYear,
      targetMonth + 1,
      0,
    ).day; // Hedef ayın son günü (ertesi ayın 0. günü hilesi)

    return DateTime(
      targetYear,
      targetMonth,
      startDate.day.clamp(1, lastDay),
    ); // Gün ayda yoksa (31 Ocak+1 ay) son güne çek
  }

  /// Başlangıç ile bitiş arasındaki tam ay sayısı (ay sonuna taşmayı hesaba katar).
  static int wholeMonthsBetween(DateTime start, DateTime end) {
    final s = dateOnly(start);
    final e = dateOnly(end);
    var months = (e.year - s.year) * 12 + e.month - s.month;
    if (months < 1) return 0;
    while (months > 0 &&
        addDuration(
          s,
          unit: ContractDurationUnit.month,
          count: months,
        ).isAfter(e)) {
      months--;
    }
    return months;
  }

  /// Toplam kiralama süresi: "11 ay", "2 yıl", "1 yıl 3 ay" veya "20 gün".
  static String durationLabel(DateTime start, DateTime end) {
    // Bitiş günü kiralamaya dahildir (01.01 - 31.12 = 12 ay); bu yüzden
    // süre, bitişin ertesi gününe kadar sayılır.
    final inclusiveEnd = DateTime(end.year, end.month, end.day + 1);
    final months = wholeMonthsBetween(start, inclusiveEnd);
    if (months < 1) {
      final days = DateTime.utc(
        inclusiveEnd.year,
        inclusiveEnd.month,
        inclusiveEnd.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      return '${days < 0 ? 0 : days} Gün';
    }
    final years = months ~/ 12;
    final rest = months % 12;
    if (years == 0) return '$months Ay';
    if (rest == 0) return '$years Yıl';
    return '$years Yıl $rest Ay';
  }

  static DateTime dateOnly(
    DateTime value,
  ) => // Saati sıfırlayıp yalnız tarihi döndürür
  DateTime(
    value.year,
    value.month,
    value.day,
  ); // Yıl-ay-gün ile saatsiz yeni tarih
}
