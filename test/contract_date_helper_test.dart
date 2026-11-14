import 'package:flutter_test/flutter_test.dart';

import 'package:dere_sozlesme_takip/core/utils/contract_date_helper.dart';
import 'package:dere_sozlesme_takip/models/contract_model.dart';

void main() {
  test('monthly duration clamps to the last day of shorter months', () {
    expect(
      ContractDateHelper.addDuration(
        DateTime(2026, 1, 31),
        unit: ContractDurationUnit.month,
        count: 1,
      ),
      DateTime(2026, 2, 28),
    );
  });

  test('yearly duration handles leap-day starts', () {
    expect(
      ContractDateHelper.addDuration(
        DateTime(2024, 2, 29),
        unit: ContractDurationUnit.year,
        count: 1,
      ),
      DateTime(2025, 2, 28),
    );
  });

  test('duration count supports multiple months and years', () {
    expect(
      ContractDateHelper.addDuration(
        DateTime(2026, 6, 15),
        unit: ContractDurationUnit.month,
        count: 3,
      ),
      DateTime(2026, 9, 15),
    );
    expect(
      ContractDateHelper.addDuration(
        DateTime(2026, 6, 15),
        unit: ContractDurationUnit.year,
        count: 2,
      ),
      DateTime(2028, 6, 15),
    );
  });
}
