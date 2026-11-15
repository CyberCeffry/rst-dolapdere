class BusinessDayHelper {
  const BusinessDayHelper._();

  static DateTime nextWorkingDay(DateTime date, List<int> workingDays) {
    if (workingDays.isEmpty ||
        workingDays.any(
          (weekday) => weekday < DateTime.monday || weekday > DateTime.sunday,
        )) {
      throw ArgumentError.value(
        workingDays,
        'workingDays',
        'At least one valid weekday must be selected.',
      );
    }

    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    for (var daysAhead = 0; daysAhead < DateTime.daysPerWeek; daysAhead++) {
      final candidate = dateOnly.add(Duration(days: daysAhead));
      if (workingDays.contains(candidate.weekday)) {
        return DateTime(candidate.year, candidate.month, candidate.day);
      }
    }
    throw StateError('A working day could not be found.');
  }

  static int daysRemaining(DateTime expiryDate, DateTime notificationDate) {
    final expiry = DateTime.utc(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    );
    final notification = DateTime.utc(
      notificationDate.year,
      notificationDate.month,
      notificationDate.day,
    );
    return expiry.difference(notification).inDays;
  }
}
