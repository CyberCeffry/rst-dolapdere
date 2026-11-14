enum ContractHistoryAction { created, renewed, ended, activated, assigned }

class ContractHistoryEntry {
  const ContractHistoryEntry({
    required this.action,
    required this.occurredAt,
    this.previousEndDate,
    this.newEndDate,
    this.previousMonthlyPrice,
    this.newMonthlyPrice,
    this.actorUid,
    this.actorUsername,
    this.targetUsername,
  });

  final ContractHistoryAction action;
  final DateTime occurredAt;
  final DateTime? previousEndDate;
  final DateTime? newEndDate;
  final double? previousMonthlyPrice;
  final double? newMonthlyPrice;
  final String? actorUid;
  final String? actorUsername;
  final String? targetUsername;

  factory ContractHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ContractHistoryEntry(
        action: ContractHistoryAction.values.firstWhere(
          (action) => action.name == json['action'],
          orElse: () => ContractHistoryAction.created,
        ),
        occurredAt:
            DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
            DateTime.now(),
        previousEndDate: DateTime.tryParse(
          json['previousEndDate'] as String? ?? '',
        ),
        newEndDate: DateTime.tryParse(json['newEndDate'] as String? ?? ''),
        previousMonthlyPrice: (json['previousMonthlyPrice'] as num?)
            ?.toDouble(),
        newMonthlyPrice: (json['newMonthlyPrice'] as num?)?.toDouble(),
        actorUid: json['actorUid'] as String?,
        actorUsername: json['actorUsername'] as String?,
        targetUsername: json['targetUsername'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'action': action.name,
    'occurredAt': occurredAt.toIso8601String(),
    'previousEndDate': previousEndDate?.toIso8601String(),
    'newEndDate': newEndDate?.toIso8601String(),
    'previousMonthlyPrice': previousMonthlyPrice,
    'newMonthlyPrice': newMonthlyPrice,
    'actorUid': actorUid,
    'actorUsername': actorUsername,
    'targetUsername': targetUsername,
  };
}
