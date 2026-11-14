import 'date_helper.dart';

class ContractRemainingTime {
  static int daysUntil(DateTime endDate, {DateTime? today}) =>
      DateHelper.daysUntil(endDate, from: today);

  static String format(int days) {
    if (days < 30) return '$days gün';
    if (days <= 365) return '${days ~/ 30} ay';
    return '${days ~/ 365} yıl';
  }

  static bool isUrgent(int days) => days >= 0 && days < 15;
}
