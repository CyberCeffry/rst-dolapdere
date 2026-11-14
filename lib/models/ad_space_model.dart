class AdSpaceModel {
  const AdSpaceModel({
    required this.id,
    required this.name,
    this.location = '',
    this.description = '',
    this.monthlyPrice = 0,
    this.isAvailable = true,
  });

  final String id;
  final String name;
  final String location;
  final String description;
  final double monthlyPrice;
  final bool isAvailable;

  factory AdSpaceModel.fromJson(Map<String, dynamic> json) => AdSpaceModel(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    location: json['location'] as String? ?? '',
    description: json['description'] as String? ?? '',
    monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,
    isAvailable: json['isAvailable'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': location,
    'description': description,
    'monthlyPrice': monthlyPrice,
    'isAvailable': isAvailable,
  };
}
