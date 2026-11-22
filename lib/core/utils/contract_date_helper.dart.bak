import '../../models/contract_model.dart';

class ContractDateHelper {
  static DateTime addDuration(
    DateTime startDate, {
    required ContractDurationUnit unit,
    required int count,
  }) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'Süre en az 1 olmalıdır.');
    }

    final totalMonths = unit == ContractDurationUnit.year ? count * 12 : count;
    final targetMonthIndex = startDate.month - 1 + totalMonths;
    final targetYear = startDate.year + targetMonthIndex ~/ 12;
    final targetMonth = targetMonthIndex % 12 + 1;
    final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;

    return DateTime(targetYear, targetMonth, startDate.day.clamp(1, lastDay));
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
