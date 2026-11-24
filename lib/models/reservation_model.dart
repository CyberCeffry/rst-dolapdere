/// Bir reklam alanı için, mevcut kiracıdan sonraki kullanıcı adına yapılan rezervasyon.
class ReservationModel {
  const ReservationModel({
    required this.id,
    required this.adSpaceId,
    required this.customerId,
    required this.createdAt,
    this.notes = '',
  });

  final String id;
  final String adSpaceId; // Rezerve edilen reklam alanı
  final String customerId; // Rezerve eden (sıradaki) müşteri
  final DateTime createdAt; // Rezervasyonun yapıldığı tarih
  final String notes;

  factory ReservationModel.fromJson(Map<String, dynamic> json) =>
      ReservationModel(
        id: json['id'] as String,
        adSpaceId: json['adSpaceId'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'adSpaceId': adSpaceId,
    'customerId': customerId,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
  };
}