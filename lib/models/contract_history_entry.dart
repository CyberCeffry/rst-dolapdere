enum ContractHistoryAction { created, renewed, ended, activated, assigned }  // Geçmişte kaydedilen işlem türleri: oluşturuldu, yenilendi, bitirildi, aktifleştirildi, kullanıcıya atandı

class ContractHistoryEntry {  // Sözleşmenin geçmişindeki tek bir olay kaydı
  const ContractHistoryEntry({  // Sabit yapıcı
    required this.action,  // Ne yapıldı (zorunlu)
    required this.occurredAt,  // Ne zaman yapıldı (zorunlu)
    this.previousEndDate,  // Önceki bitiş tarihi (yenilemede dolar)
    this.newEndDate,  // Yeni bitiş tarihi
    this.previousMonthlyPrice,  // Önceki aylık fiyat
    this.newMonthlyPrice,  // Yeni aylık fiyat
    this.actorUid,  // İşlemi yapan kullanıcının kimliği
    this.actorUsername,  // İşlemi yapan kullanıcının adı
    this.targetUsername,  // İşlemin atandığı kullanıcı adı
  });

  final ContractHistoryAction action;  // İşlem türü
  final DateTime occurredAt;  // İşlem zamanı
  final DateTime? previousEndDate;  // Eski bitiş (boş olabilir)
  final DateTime? newEndDate;  // Yeni bitiş (boş olabilir)
  final double? previousMonthlyPrice;  // Eski fiyat (boş olabilir)
  final double? newMonthlyPrice;  // Yeni fiyat (boş olabilir)
  final String? actorUid;  // İşlemi yapanın kimliği
  final String? actorUsername;  // İşlemi yapanın adı
  final String? targetUsername;  // Hedef kullanıcı adı

  factory ContractHistoryEntry.fromJson(Map<String, dynamic> json) =>  // JSON'dan geçmiş kaydı üretir
      ContractHistoryEntry(  // Okunan alanlarla nesne oluşturur
        action: ContractHistoryAction.values.firstWhere(  // Metin olarak saklanan işlem adını enum'a çevirir
          (action) => action.name == json['action'],  // Adı eşleşen enum değerini bul
          orElse: () => ContractHistoryAction.created,  // Eşleşme yoksa 'oluşturuldu' kabul et
        ),
        occurredAt:  // Zaman alanı
            DateTime.tryParse(json['occurredAt'] as String? ?? '') ??  // Metni tarihe çevirmeyi dene
            DateTime.now(),  // Çevrilemezse şu anı kullan
        previousEndDate: DateTime.tryParse(  // Eski bitiş tarihini çevirmeyi dene
          json['previousEndDate'] as String? ?? '',  // Alan yoksa boş metin ver (tryParse null döner)
        ),
        newEndDate: DateTime.tryParse(json['newEndDate'] as String? ?? ''),  // Yeni bitiş tarihini çevir
        previousMonthlyPrice: (json['previousMonthlyPrice'] as num?)  // Eski fiyatı sayı olarak oku
            ?.toDouble(),  // Sayı varsa double'a çevir
        newMonthlyPrice: (json['newMonthlyPrice'] as num?)?.toDouble(),  // Yeni fiyatı oku
        actorUid: json['actorUid'] as String?,  // İşlemi yapan kimliği oku
        actorUsername: json['actorUsername'] as String?,  // İşlemi yapan adı oku
        targetUsername: json['targetUsername'] as String?,  // Hedef kullanıcıyı oku
      );

  Map<String, dynamic> toJson() => {  // Kaydı JSON haritasına çevirir
    'action': action.name,  // Enum'u metin olarak sakla
    'occurredAt': occurredAt.toIso8601String(),  // Tarihi ISO-8601 metni olarak sakla
    'previousEndDate': previousEndDate?.toIso8601String(),  // Eski bitiş tarihi (varsa metin)
    'newEndDate': newEndDate?.toIso8601String(),  // Yeni bitiş tarihi (varsa metin)
    'previousMonthlyPrice': previousMonthlyPrice,  // Eski fiyat
    'newMonthlyPrice': newMonthlyPrice,  // Yeni fiyat
    'actorUid': actorUid,  // İşlemi yapanın kimliği
    'actorUsername': actorUsername,  // İşlemi yapanın adı
    'targetUsername': targetUsername,  // Hedef kullanıcı
  };
}