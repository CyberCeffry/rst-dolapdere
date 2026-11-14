class DateHelper {
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int daysUntil(DateTime value, {DateTime? from}) =>
      dateOnly(value).difference(dateOnly(from ?? DateTime.now())).inDays;

  static bool isOnOrAfterToday(DateTime value, {DateTime? today}) =>
      !dateOnly(value).isBefore(dateOnly(today ?? DateTime.now()));

  static bool isOnOrBeforeToday(DateTime value, {DateTime? today}) =>
      !dateOnly(value).isAfter(dateOnly(today ?? DateTime.now()));
}
