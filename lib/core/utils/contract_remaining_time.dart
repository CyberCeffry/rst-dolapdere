import 'date_helper.dart';  // Gün farkı hesaplayan yardımcı

class ContractRemainingTime {  // Kalan süreyi hesaplayıp yazıya çeviren yardımcı
  static int daysUntil(DateTime endDate, {DateTime? today}) =>  // Bitişe kaç gün kaldığını verir
      DateHelper.daysUntil(endDate, from: today);  // Asıl hesabı DateHelper yapar; today verilmezse bugün

  static String format(int days) {  // Gün sayısını okunur metne çevirir
    if (days < 30) return '$days gün';  // 30 günden azsa gün olarak yaz
    if (days <= 365) return '${days ~/ 30} ay';  // Bir yıla kadar ay olarak yaz (30'a böl)
    return '${days ~/ 365} yıl';  // Daha uzunsa yıl olarak yaz
  }

  static bool isUrgent(int days) => days >= 0 && days < 15;

  /// Ayrıntılı kalan süre: "25 gün", "1 ay 8 gün", "3 ay".
  /// Sözleşmeler ekranındaki "Aktif • 1 ay 8 gün kaldı" ile aynı hesabı yapar.
  static String formatDetailed(DateTime endDate, {DateTime? today}) {
    final days = daysUntil(endDate, today: today);
    if (days <= 30) return '$days gün';
    final now = today ?? DateTime.now();
    final start = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    var months = (end.year - start.year) * 12 + end.month - start.month;
    if (end.day < start.day) months--;
    if (months < 1) return '$days gün';
    // Bugünden "months" ay sonrası (ay sonuna taşarsa ayın son günü).
    final anchorMonth = start.month + months;
    final lastDay = DateTime.utc(start.year, anchorMonth + 1, 0).day;
    final anchor = DateTime.utc(
      start.year,
      anchorMonth,
      start.day > lastDay ? lastDay : start.day,
    );
    final extraDays = end.difference(anchor).inDays;
    return extraDays > 0 ? '$months ay $extraDays gün' : '$months ay';
  }  // 0-14 gün arası 'acil' sayılır
}