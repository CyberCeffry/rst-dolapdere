import 'contract_history_entry.dart';  // Sözleşme geçmişi kayıt sınıfı

enum ContractDurationUnit { month, year }  // Sözleşme süresi birimi: ay veya yıl

class ContractModel {  // Bir kira sözleşmesini temsil eden veri sınıfı
  const ContractModel({  // Sabit yapıcı
    required this.id,  // Sözleşme kimliği
    required this.customerId,  // Kiracı (müşteri) kimliği
    required this.adSpaceId,  // Kiralanan reklam alanının kimliği
    required this.startDate,  // Başlangıç tarihi
    required this.endDate,  // Bitiş tarihi
    this.monthlyPrice = 0,  // Aylık kira; varsayılan 0
    this.durationUnit = ContractDurationUnit.year,  // Süre birimi; varsayılan yıl
    this.durationCount = 1,  // Süre adedi; varsayılan 1
    this.notes = '',  // Notlar; varsayılan boş
    this.isActive = true,  // Aktif mi; varsayılan evet
    this.isFinalized = false,  // Elle bitirildi mi; varsayılan hayır
    this.finalizedAt,  // Bitirilme zamanı
    this.renewedFromContractId,  // Hangi sözleşmenin yenilemesi olduğu
    this.history = const [],  // Olay geçmişi; varsayılan boş liste
    this.responsibleUserId,  // Sorumlu kullanıcı kimliği
    this.responsibleUsername,  // Sorumlu kullanıcı adı
    this.pdfPath,  // Ekli PDF'in göreli yolu
  });

  final String id;  // Sözleşme kimliği
  final String customerId;  // Müşteri bağlantısı
  final String adSpaceId;  // Reklam alanı bağlantısı
  final DateTime startDate;  // Başlangıç
  final DateTime endDate;  // Bitiş
  final double monthlyPrice;  // Aylık bedel
  final ContractDurationUnit durationUnit;  // Süre birimi
  final int durationCount;  // Süre adedi (ör. 2 yıl → 2)
  final String notes;  // Serbest notlar
  final bool isActive;  // Aktif/pasif anahtarı
  final bool isFinalized;  // Sözleşme sonlandırıldı mı
  final DateTime? finalizedAt;  // Sonlandırma tarihi (boş olabilir)
  final String? renewedFromContractId;  // Yenileme zinciri için önceki sözleşme
  final List<ContractHistoryEntry> history;  // Sözleşme geçmişi listesi
  final String? responsibleUserId;  // Sorumlu kullanıcı kimliği
  final String? responsibleUsername;  // Sorumlu kullanıcı adı

  /// Sözleşme PDF'inin 'sözleşmeler' klasörüne göre göreli yolu.
  final String? pdfPath;  // PDF'in 'sözleşmeler' klasörüne göre yolu

  bool get hasPdf => (pdfPath ?? '').trim().isNotEmpty;  // PDF eklenmiş mi? (boşluk dışında karakter var mı)

  factory ContractModel.fromJson(Map<String, dynamic> json) => ContractModel(  // JSON'dan sözleşme üretir
    id: json['id'] as String,  // Kimlik zorunlu
    customerId: json['customerId'] as String? ?? '',  // Müşteri kimliği yoksa boş
    adSpaceId: json['adSpaceId'] as String? ?? '',  // Alan kimliği yoksa boş
    startDate:  // Başlangıç tarihi
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now(),  // Metni tarihe çevir; olmazsa şimdi
    endDate:  // Bitiş tarihi
        DateTime.tryParse(json['endDate'] as String? ?? '') ?? DateTime.now(),  // Metni tarihe çevir; olmazsa şimdi
    monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,  // Fiyatı double yap; yoksa 0
    durationUnit: ContractDurationUnit.values.firstWhere(  // Metin olarak saklanan birimi enum'a çevir
      (unit) => unit.name == json['durationUnit'],  // Adı eşleşen birimi bul
      orElse: () => ContractDurationUnit.year,  // Bulunamazsa yıl kabul et
    ),
    durationCount: (json['durationCount'] as num?)?.toInt() ?? 1,  // Süre adedini tamsayı yap; yoksa 1
    notes: json['notes'] as String? ?? '',  // Not yoksa boş
    isActive: json['isActive'] as bool? ?? true,  // Değer yoksa aktif
    isFinalized: json['isFinalized'] as bool? ?? false,  // Değer yoksa bitirilmemiş
    finalizedAt: DateTime.tryParse(json['finalizedAt'] as String? ?? ''),  // Bitirilme tarihini çevir
    renewedFromContractId: json['renewedFromContractId'] as String?,  // Yenileme kaynağını oku
    responsibleUserId: json['responsibleUserId'] as String?,  // Sorumlu kimliğini oku
    responsibleUsername: json['responsibleUsername'] as String?,  // Sorumlu adını oku
    pdfPath: json['pdfPath'] as String?,  // PDF yolunu oku
    history: (json['history'] as List<dynamic>? ?? const [])  // Geçmiş listesini al; yoksa boş liste
        .map(  // Her öğeyi dönüştür
          (entry) => ContractHistoryEntry.fromJson(  // Her öğeden geçmiş kaydı üret
            Map<String, dynamic>.from(entry as Map),  // Öğeyi tipli haritaya çevir
          ),
        )
        .toList(),  // Sonucu listeye topla
  );

  Map<String, dynamic> toJson() => {  // Sözleşmeyi JSON haritasına çevirir
    'id': id,  // Kimlik
    'customerId': customerId,  // Müşteri kimliği
    'adSpaceId': adSpaceId,  // Alan kimliği
    'startDate': startDate.toIso8601String(),  // Başlangıç (ISO metin)
    'endDate': endDate.toIso8601String(),  // Bitiş (ISO metin)
    'monthlyPrice': monthlyPrice,  // Aylık bedel
    'durationUnit': durationUnit.name,  // Birim adı (metin)
    'durationCount': durationCount,  // Süre adedi
    'notes': notes,  // Notlar
    'isActive': isActive,  // Aktiflik
    'isFinalized': isFinalized,  // Sonlandırıldı mı
    'finalizedAt': finalizedAt?.toIso8601String(),  // Sonlandırma tarihi (varsa)
    'renewedFromContractId': renewedFromContractId,  // Yenileme kaynağı
    'responsibleUserId': responsibleUserId,  // Sorumlu kimliği
    'responsibleUsername': responsibleUsername,  // Sorumlu adı
    'pdfPath': pdfPath,  // PDF yolu
    'history': history.map((entry) => entry.toJson()).toList(),  // Geçmiş kayıtlarını JSON listesine çevir
  };
}