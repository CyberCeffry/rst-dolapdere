import 'package:flutter_test/flutter_test.dart';

import 'package:dere_sozlesme_takip/core/utils/business_day_helper.dart';

void main() {
  const weekdays = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  test(
    'moves a Saturday reminder to Monday and recalculates remaining days',
    () {
      final saturday = DateTime(2026, 11, 28);
      final expiry = DateTime(2026, 12, 13);

      final deliveryDate = BusinessDayHelper.nextWorkingDay(saturday, weekdays);

      expect(deliveryDate, DateTime(2026, 11, 30));
      expect(BusinessDayHelper.daysRemaining(expiry, deliveryDate), 13);
    },
  );

  test('keeps a selected day and skips consecutive non-working days', () {
    final friday = DateTime(2026, 11, 27);
    final tuesdayOnly = [DateTime.tuesday];

    expect(
      BusinessDayHelper.nextWorkingDay(friday, tuesdayOnly),
      DateTime(2026, 12, 1),
    );
    expect(
      BusinessDayHelper.nextWorkingDay(DateTime(2026, 12, 1), tuesdayOnly),
      DateTime(2026, 12, 1),
    );
  });
}
