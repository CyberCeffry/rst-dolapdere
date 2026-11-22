import 'contract_history_entry.dart';

enum ContractDurationUnit { month, year }

class ContractModel {
  const ContractModel({
    required this.id,
    required this.customerId,
    required this.adSpaceId,
    required this.startDate,
    required this.endDate,
    this.monthlyPrice = 0,
    this.durationUnit = ContractDurationUnit.year,
    this.durationCount = 1,
    this.notes = '',
    this.isActive = true,
    this.isFinalized = false,
    this.finalizedAt,
    this.renewedFromContractId,
    this.history = const [],
    this.responsibleUserId,
    this.responsibleUsername,
    this.pdfPath,
  });

  final String id;
  final String customerId;
  final String adSpaceId;
  final DateTime startDate;
  final DateTime endDate;
  final double monthlyPrice;
  final ContractDurationUnit durationUnit;
  final int durationCount;
  final String notes;
  final bool isActive;
  final bool isFinalized;
  final DateTime? finalizedAt;
  final String? renewedFromContractId;
  final List<ContractHistoryEntry> history;
  final String? responsibleUserId;
  final String? responsibleUsername;

  /// Sözleşme PDF'inin 'sözleşmeler' klasörüne göre göreli yolu.
  final String? pdfPath;

  bool get hasPdf => (pdfPath ?? '').trim().isNotEmpty;

  factory ContractModel.fromJson(Map<String, dynamic> json) => ContractModel(
    id: json['id'] as String,
    customerId: json['customerId'] as String? ?? '',
    adSpaceId: json['adSpaceId'] as String? ?? '',
    startDate:
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now(),
    endDate:
        DateTime.tryParse(json['endDate'] as String? ?? '') ?? DateTime.now(),
    monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0,
    durationUnit: ContractDurationUnit.values.firstWhere(
      (unit) => unit.name == json['durationUnit'],
      orElse: () => ContractDurationUnit.year,
    ),
    durationCount: (json['durationCount'] as num?)?.toInt() ?? 1,
    notes: json['notes'] as String? ?? '',
    isActive: json['isActive'] as bool? ?? true,
    isFinalized: json['isFinalized'] as bool? ?? false,
    finalizedAt: DateTime.tryParse(json['finalizedAt'] as String? ?? ''),
    renewedFromContractId: json['renewedFromContractId'] as String?,
    responsibleUserId: json['responsibleUserId'] as String?,
    responsibleUsername: json['responsibleUsername'] as String?,
    pdfPath: json['pdfPath'] as String?,
    history: (json['history'] as List<dynamic>? ?? const [])
        .map(
          (entry) => ContractHistoryEntry.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'customerId': customerId,
    'adSpaceId': adSpaceId,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'monthlyPrice': monthlyPrice,
    'durationUnit': durationUnit.name,
    'durationCount': durationCount,
    'notes': notes,
    'isActive': isActive,
    'isFinalized': isFinalized,
    'finalizedAt': finalizedAt?.toIso8601String(),
    'renewedFromContractId': renewedFromContractId,
    'responsibleUserId': responsibleUserId,
    'responsibleUsername': responsibleUsername,
    'pdfPath': pdfPath,
    'history': history.map((entry) => entry.toJson()).toList(),
  };
}
