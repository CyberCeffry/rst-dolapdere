class AdSpaceModel {  // Bir reklam alanını (pano, cephe vb.) temsil eden veri sınıfı
  const AdSpaceModel({  // Sabit (const) yapıcı: nesne değiştirilemez
    required this.id,  // Benzersiz kimlik (zorunlu)
    required this.name,  // Alan adı (zorunlu)
    this.location = '',  // Konum; verilmezse boş metin
    this.description = '',  // Açıklama; verilmezse boş metin
    this.monthlyPrice = 0,  // Aylık kira bedeli; varsayılan 0
    this.isAvailable = true,  // Müsait mi; varsayılan evet
  });

  final String id;  // Kayıt kimliği
  final String name;  // Alanın görünen adı
  final String location;  // Alanın bulunduğu yer
  final String description;  // Serbest açıklama
  final double monthlyPrice;  // Aylık fiyat (ondalıklı)
  final bool isAvailable;  // Boşta mı (true) kirada mı (false)

  factory AdSpaceModel.fromJson(Map<String, dynamic> json) => AdSpaceModel(  // JSON haritasından nesne üretir (cihazdan/Firestore'dan okurken)
    id: json['id'] as String,  // Kimlik zorunlu; yoksa hata verir
    name: json['name'] as String? ?? '',  // Ad yoksa boş metin
    location: json['location'] as String? ?? '',  // Konum yoksa boş metin
    description: json['description'] as String? ?? '',  // Açıklama yoksa boş metin
    monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,  // Sayıyı double'a çevirir; yoksa 0
    isAvailable: json['isAvailable'] as bool? ?? true,  // Değer yoksa müsait kabul eder
  );

  Map<String, dynamic> toJson() => {  // Nesneyi JSON haritasına çevirir (kaydederken)
    'id': id,  // Kimlik alanı
    'name': name,  // Ad alanı
    'location': location,  // Konum alanı
    'description': description,  // Açıklama alanı
    'monthlyPrice': monthlyPrice,  // Fiyat alanı
    'isAvailable': isAvailable,  // Müsaitlik alanı
  };
}