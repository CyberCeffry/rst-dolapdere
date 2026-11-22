import 'date_helper.dart';  // Gün farkı hesaplayan yardımcı

class ContractRemainingTime {  // Kalan süreyi hesaplayıp yazıya çeviren yardımcı
  static int daysUntil(DateTime endDate, {DateTime? today}) =>  // Bitişe kaç gün kaldığını verir
      DateHelper.daysUntil(endDate, from: today);  // Asıl hesabı DateHelper yapar; today verilmezse bugün

  static String format(int days) {  // Gün sayısını okunur metne çevirir
    if (days < 30) return '$days gün';  // 30 günden azsa gün olarak yaz
    if (days <= 365) return '${days ~/ 30} ay';  // Bir yıla kadar ay olarak yaz (30'a böl)
    return '${days ~/ 365} yıl';  // Daha uzunsa yıl olarak yaz
  }

  static bool isUrgent(int days) => days >= 0 && days < 15;  // 0-14 gün arası 'acil' sayılır
}