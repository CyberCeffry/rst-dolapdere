/// Reklam alanı fiyat listesi kaydı. Sözleşmelerden, kiracılardan ve reklam
/// alanının kendi kira alanından TAMAMEN bağımsızdır; yalnızca "Reklam
/// Fiyatları" ekranından değişir. Kimliği, bağlı reklam alanının kimliğidir.
class AdPriceModel {
  const AdPriceModel({
    required this.id,
    required this.adSpaceId,
    required this.monthly,
    required this.threeMonth,
    required this.sixMonth,
    required this.twelveMonth,
    required this.updatedAt,
  });

  final String id;
  final String adSpaceId;

  final double monthly; // 1 aylık fiyat
  final double threeMonth; // 3 aylık fiyat
  final double sixMonth; // 6 aylık fiyat
  final double twelveMonth; // 12 aylık (yıllık) fiyat

  final DateTime updatedAt;

  /// Dört fiyatın da girilmiş olması.
  bool get isComplete =>
      monthly > 0 && threeMonth > 0 && sixMonth > 0 && twelveMonth > 0;

  factory AdPriceModel.fromJson(Map<String, dynamic> json) => AdPriceModel(
    id: json['id'] as String,
    adSpaceId: json['adSpaceId'] as String? ?? (json['id'] as String),
    monthly: (json['monthly'] as num?)?.toDouble() ?? 0,
    threeMonth: (json['threeMonth'] as num?)?.toDouble() ?? 0,
    sixMonth: (json['sixMonth'] as num?)?.toDouble() ?? 0,
    twelveMonth: (json['twelveMonth'] as num?)?.toDouble() ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'adSpaceId': adSpaceId,
    'monthly': monthly,
    'threeMonth': threeMonth,
    'sixMonth': sixMonth,
    'twelveMonth': twelveMonth,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
