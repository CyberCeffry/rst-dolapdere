import '../../models/contract_model.dart';  // ContractDurationUnit enum'u için

class ContractDateHelper {  // Sözleşme tarihi hesaplayan yardımcı (nesne üretilmez, static)
  static DateTime addDuration(  // Başlangıca ay/yıl ekleyip bitiş tarihini hesaplar
    DateTime startDate, {  // Başlangıç tarihi
    required ContractDurationUnit unit,  // Birim: ay veya yıl
    required int count,  // Kaç birim eklenecek
  }) {  // Metot gövdesi başlar
    if (count < 1) {  // Süre 1'den küçükse geçersiz
      throw ArgumentError.value(count, 'count', 'Süre en az 1 olmalıdır.');  // Hata fırlatıp işlemi durdur
    }

    final totalMonths = unit == ContractDurationUnit.year ? count * 12 : count;  // Her şeyi aya çevir (yıl × 12)
    final targetMonthIndex = startDate.month - 1 + totalMonths;  // 0 tabanlı hedef ay sırası (Ocak=0)
    final targetYear = startDate.year + targetMonthIndex ~/ 12;  // Taşan ayları yıla ekle (tamsayı bölme)
    final targetMonth = targetMonthIndex % 12 + 1;  // Yıl içindeki ay (1-12)
    final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;  // Hedef ayın son günü (ertesi ayın 0. günü hilesi)

    return DateTime(targetYear, targetMonth, startDate.day.clamp(1, lastDay));  // Gün ayda yoksa (31 Ocak+1 ay) son güne çek
  }

  static DateTime dateOnly(DateTime value) =>  // Saati sıfırlayıp yalnız tarihi döndürür
      DateTime(value.year, value.month, value.day);  // Yıl-ay-gün ile saatsiz yeni tarih
}