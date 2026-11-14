import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/features/dashboard/screens/dashboard_screen.dart';
import 'package:dere_sozlesme_takip/features/records/management_screens.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/contract_model.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('contract detail shows extension history and delete action', (
    tester,
  ) async {
    final store = await _createStore();
    final original = store.contracts.single;
    await store.renewContract(
      original.id,
      ContractModel(
        id: 'renewed-id',
        customerId: original.customerId,
        adSpaceId: original.adSpaceId,
        startDate: original.startDate,
        endDate: DateTime.now().add(const Duration(days: 60)),
        monthlyPrice: original.monthlyPrice,
      ),
    );
    await tester.pumpWidget(_managementApp(store, RecordType.contracts));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kayıt işlemleri'));
    await tester.pumpAndSettle();
    expect(find.text('Sil'), findsOneWidget);
    await tester.tap(find.text('Detayları görüntüle'));
    await tester.pumpAndSettle();

    expect(find.text('Hareketler'), findsOneWidget);
    expect(find.text('Sözleşme eklendi'), findsOneWidget);
    expect(find.text('Sözleşme uzatıldı'), findsOneWidget);
  });

  testWidgets('tenant detail lists rented ad space and contract period', (
    tester,
  ) async {
    final store = await _createStore();
    await tester.pumpWidget(_managementApp(store, RecordType.customers));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kayıt işlemleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detayları görüntüle'));
    await tester.pumpAndSettle();

    expect(find.text('Kiralanan alanlar'), findsOneWidget);
    expect(find.text('Dolu Pano'), findsOneWidget);
    expect(find.textContaining('Aktif'), findsOneWidget);
  });

  testWidgets('active contract can be deleted after confirmation', (
    tester,
  ) async {
    final store = await _createStore();
    await tester.pumpWidget(_managementApp(store, RecordType.contracts));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kayıt işlemleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(store.contracts, isEmpty);
  });

  testWidgets('ended contract can be deleted after confirmation', (
    tester,
  ) async {
    final store = await _createStore();
    await store.markContractEnded(store.contracts.single.id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagementScreen(
            store: store,
            type: RecordType.contracts,
            showEndedContracts: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kayıt işlemleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(store.contracts, isEmpty);
  });

  testWidgets('dashboard summary cards report their navigation destinations', (
    tester,
  ) async {
    final store = await _createStore();
    final destinations = <DashboardDestination>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(store: store, onNavigate: destinations.add),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toplam Reklam Alanı'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boş Reklam Alanları'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aktif Sözleşmeler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Süresi Yaklaşan'));
    await tester.pumpAndSettle();

    expect(destinations, [
      DashboardDestination.adSpaces,
      DashboardDestination.availableAdSpaces,
      DashboardDestination.activeContracts,
      DashboardDestination.expiringContracts,
    ]);
  });
}

Widget _managementApp(AppStore store, RecordType type) => MaterialApp(
  home: Scaffold(
    body: ManagementScreen(store: store, type: type),
  ),
);

Future<AppStore> _createStore() async {
  final store = await AppStore.initialize();
  final today = DateTime.now();
  await store.saveCustomer(
    const CustomerModel(id: 'customer-1', name: 'Kiracı'),
  );
  await store.saveAdSpace(
    const AdSpaceModel(id: 'space-1', name: 'Dolu Pano', location: 'Merkez'),
  );
  await store.saveContract(
    ContractModel(
      id: 'contract-1',
      customerId: 'customer-1',
      adSpaceId: 'space-1',
      startDate: today.subtract(const Duration(days: 1)),
      endDate: today.add(const Duration(days: 30)),
      monthlyPrice: 12000,
    ),
  );
  return store;
}
