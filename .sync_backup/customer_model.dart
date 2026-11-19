class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.name,
    this.company = '',
    this.phone = '',
    this.email = '',
    this.notes = '',
  });

  final String id;
  final String name;
  final String company;
  final String phone;
  final String email;
  final String notes;

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    company: json['company'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'phone': phone,
    'email': email,
    'notes': notes,
  };
}
