class CustomerModel {  // Müşteri (kiracı firma) veri sınıfı
  const CustomerModel({  // Sabit yapıcı
    required this.id,  // Müşteri kimliği
    required this.name,  // Görünen ad
    this.company = '',  // Firma adı
    this.address = '',  // Adres
    this.phone = '',  // Telefon
    this.email = '',  // E-posta
    this.notes = '',  // Notlar
  });

  /// Görünen ad. Artık firma adıyla aynı tutulur (eski kayıtlarda kişi adı olabilir).
  final String id;  // Kimlik
  final String name;  // Ad (artık firma adıyla aynı tutuluyor)
  final String company;  // Firma
  final String address;  // Adres
  final String phone;  // Telefon
  final String email;  // E-posta
  final String notes;  // Notlar

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(  // JSON'dan müşteri üretir
    id: json['id'] as String,  // Kimlik zorunlu
    name: json['name'] as String? ?? '',  // Ad yoksa boş
    company: json['company'] as String? ?? '',  // Firma yoksa boş
    address: json['address'] as String? ?? '',  // Adres yoksa boş
    phone: json['phone'] as String? ?? '',  // Telefon yoksa boş
    email: json['email'] as String? ?? '',  // E-posta yoksa boş
    notes: json['notes'] as String? ?? '',  // Not yoksa boş
  );

  Map<String, dynamic> toJson() => {  // Müşteriyi JSON haritasına çevirir
    'id': id,  // Kimlik
    'name': name,  // Ad
    'company': company,  // Firma
    'address': address,  // Adres
    'phone': phone,  // Telefon
    'email': email,  // E-posta
    'notes': notes,  // Notlar
  };
}