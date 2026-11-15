import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/contract_history_entry.dart';
import 'package:dere_sozlesme_takip/models/contract_model.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('theme preference persists across app store instances', () async {
    final store = await AppStore.initialize();
    expect(store.themeMode.value, ThemeMode.system);

    await store.setThemeMode(ThemeMode.dark);
    store.dispose();

    final restored = await AppStore.initialize();
    expect(restored.themeMode.value, ThemeMode.dark);
  });

  test(
    'records persist and active contracts mark an ad space occupied',
    () async {
      final store = await AppStore.initialize();
      final today = DateTime.now();
      await store.saveCustomer(
        const CustomerModel(id: 'customer-1', name: 'Kiracı'),
      );
      await store.saveAdSpace(
        const AdSpaceModel(id: 'space-1', name: 'Pano 1'),
      );
      await store.saveContract(
        ContractModel(
          id: 'contract-1',
          customerId: 'customer-1',
          adSpaceId: 'space-1',
          startDate: today.subtract(const Duration(days: 30)),
          endDate: today.add(const Duration(days: 5)),
          monthlyPrice: 12000,
        ),
      );

      expect(store.activeContracts, hasLength(1));
      expect(store.expiringContracts, hasLength(1));
      expect(store.adSpaces.single.isAvailable, isFalse);

      final restored = await AppStore.initialize();
      expect(restored.customers.single.name, 'Kiracı');
      expect(restored.contracts.single.monthlyPrice, 12000);
      expect(restored.adSpaces.single.isAvailable, isFalse);
    },
  );

  test('rejects overlapping active contracts on the same ad space', () async {
    final store = await AppStore.initialize();
    final today = DateTime.now();
    await store.saveCustomer(
      const CustomerModel(id: 'customer-1', name: 'Bir'),
    );
    await store.saveCustomer(
      const CustomerModel(id: 'customer-2', name: 'İki'),
    );
    await store.saveAdSpace(const AdSpaceModel(id: 'space-1', name: 'Pano 1'));
    await store.saveContract(
      ContractModel(
        id: 'contract-1',
        customerId: 'customer-1',
        adSpaceId: 'space-1',
        startDate: today,
        endDate: today.add(const Duration(days: 30)),
      ),
    );

    await expectLater(
      store.saveContract(
        ContractModel(
          id: 'contract-2',
          customerId: 'customer-2',
          adSpaceId: 'space-1',
          startDate: today.add(const Duration(days: 10)),
          endDate: today.add(const Duration(days: 40)),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('manager notification contacts persist on the device', () async {
    final store = await AppStore.initialize();
    await store.saveReminderSettings(
      phone: true,
      email: false,
      whatsapp: false,
      windows: true,
      reminderMinutes: 510,
    );
    await store.saveManagerContacts(
      email: 'yonetici@example.com',
      whatsapp: '+90 555 123 45 67',
    );

    final restored = await AppStore.initialize();
    expect(restored.managerEmail, 'yonetici@example.com');
    expect(restored.managerWhatsapp, '+90 555 123 45 67');
    expect(restored.windowsRemindersEnabled, isTrue);
    expect(restored.reminderTimeMinutes, 510);
  });

  test('finalized contracts cannot be reopened under the same id', () async {
    final store = await AppStore.initialize();
    final today = DateTime.now();
    final contract = ContractModel(
      id: 'contract-final',
      customerId: 'customer-1',
      adSpaceId: 'space-1',
      startDate: today.subtract(const Duration(days: 30)),
      endDate: today.add(const Duration(days: 30)),
    );
    await store.saveCustomer(
      const CustomerModel(id: 'customer-1', name: 'Kiracı'),
    );
    await store.saveAdSpace(const AdSpaceModel(id: 'space-1', name: 'Pano 1'));
    await store.saveContract(contract);
    await store.markContractEnded(contract.id);

    expect(store.contracts.single.isFinalized, isTrue);
    expect(store.endedContracts, hasLength(1));
    await expectLater(store.saveContract(contract), throwsA(isA<StateError>()));
  });

  test(
    'renewal extends the same contract without changing its start date',
    () async {
      final store = await AppStore.initialize();
      final original = ContractModel(
        id: 'contract-original',
        customerId: 'customer-1',
        adSpaceId: 'space-1',
        startDate: DateTime(2026, 4, 11),
        endDate: DateTime(2027, 4, 11),
        monthlyPrice: 10000,
      );
      await store.saveCustomer(
        const CustomerModel(id: 'customer-1', name: 'Kiracı'),
      );
      await store.saveAdSpace(
        const AdSpaceModel(id: 'space-1', name: 'Pano 1'),
      );
      await store.saveContract(original);
      await store.markContractEnded(original.id);
      await store.renewContract(
        original.id,
        ContractModel(
          id: 'contract-renewal',
          customerId: original.customerId,
          adSpaceId: original.adSpaceId,
          startDate: original.startDate,
          endDate: DateTime(2028, 4, 11),
          monthlyPrice: 13500,
        ),
      );

      expect(store.contracts, hasLength(1));
      final extended = store.contracts.single;
      expect(extended.id, original.id);
      expect(extended.startDate, original.startDate);
      expect(extended.endDate, DateTime(2028, 4, 11));
      expect(extended.customerId, original.customerId);
      expect(extended.adSpaceId, original.adSpaceId);
      expect(extended.monthlyPrice, 13500);
      expect(extended.isActive, isTrue);
      expect(extended.isFinalized, isFalse);

      await store.renewContract(
        original.id,
        ContractModel(
          id: 'another-generated-id',
          customerId: original.customerId,
          adSpaceId: original.adSpaceId,
          startDate: original.startDate,
          endDate: DateTime(2028, 9, 11),
          durationUnit: ContractDurationUnit.month,
          durationCount: 5,
        ),
      );

      expect(store.contracts, hasLength(1));
      expect(store.contracts.single.startDate, original.startDate);
      expect(store.contracts.single.endDate, DateTime(2028, 9, 11));
      expect(store.endedContracts, isEmpty);
      expect(store.contracts.single.history.map((entry) => entry.action), [
        ContractHistoryAction.created,
        ContractHistoryAction.ended,
        ContractHistoryAction.renewed,
        ContractHistoryAction.renewed,
      ]);

      final restored = await AppStore.initialize();
      expect(restored.contracts.single.history, hasLength(4));
    },
  );
}
