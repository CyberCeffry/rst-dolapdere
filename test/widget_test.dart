// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/core/utils/contract_date_helper.dart';
import 'package:dere_sozlesme_takip/features/notifications/screens/notification_screen.dart';
import 'package:dere_sozlesme_takip/main.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/contract_model.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  testWidgets('dashboard opens and navigation reaches ad spaces', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.initialize();
    await tester.pumpWidget(RSTDolapdereApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Toplam Reklam Alanı'), findsOneWidget);
    await tester.tap(find.text('Reklam Alanları').first);
    await tester.pumpAndSettle();
    expect(find.text('Yeni Ekle'), findsOneWidget);
  });

  testWidgets('customer form keeps email informational only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.initialize();
    await tester.pumpWidget(RSTDolapdereApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Müşteriler').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni Ekle'));
    await tester.pumpAndSettle();

    expect(find.text('E-posta (bilgi amaçlı)'), findsOneWidget);
    expect(find.text('WhatsApp numarası'), findsNothing);
  });

  testWidgets(
    'contract form defaults to one year with editable Turkish dates',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.initialize();
      await store.saveCustomer(
        const CustomerModel(id: 'customer-1', name: 'Kiracı'),
      );
      await store.saveAdSpace(
        const AdSpaceModel(id: 'space-1', name: 'Pano 1'),
      );
      await tester.pumpWidget(RSTDolapdereApp(store: store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sözleşmeler').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeni Ekle'));
      await tester.pumpAndSettle();

      expect(find.text('Sözleşme süresi'), findsOneWidget);
      expect(
        find.byType(SegmentedButton<ContractDurationUnit>),
        findsOneWidget,
      );
      expect(find.text('Aylık'), findsOneWidget);
      expect(find.text('Yıllık'), findsOneWidget);
      for (final hint in ['GG', 'AA', 'YYYY']) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.hintText == hint,
          ),
          findsNWidgets(2),
        );
      }

      final segment = tester.widget<SegmentedButton<ContractDurationUnit>>(
        find.byType(SegmentedButton<ContractDurationUnit>),
      );
      expect(segment.selected, {ContractDurationUnit.year});
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .first
            .controller
            ?.text,
        '1',
      );

      String readDatePart(String hint, int dateIndex) => tester
          .widgetList<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField && widget.decoration?.hintText == hint,
            ),
          )
          .elementAt(dateIndex)
          .controller!
          .text;

      DateTime readDate(int dateIndex) => DateTime(
        int.parse(readDatePart('YYYY', dateIndex)),
        int.parse(readDatePart('AA', dateIndex)),
        int.parse(readDatePart('GG', dateIndex)),
      );

      await tester.ensureVisible(find.text('Aylık'));
      await tester.tap(find.text('Aylık'));
      await tester.pumpAndSettle();
      expect(
        readDate(1),
        ContractDateHelper.addDuration(
          readDate(0),
          unit: ContractDurationUnit.month,
          count: 1,
        ),
      );

      final startDayField = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.hintText == 'GG',
          )
          .first;
      await tester.ensureVisible(startDayField);
      await tester.enterText(startDayField, '15');
      await tester.pumpAndSettle();
      expect(
        readDate(1),
        ContractDateHelper.addDuration(
          readDate(0),
          unit: ContractDurationUnit.month,
          count: 1,
        ),
      );

      await tester.tap(find.byTooltip('Takvimden seç').first);
      await tester.pumpAndSettle();
      final calendar = find.byType(CalendarDatePicker);
      expect(calendar, findsOneWidget);
      expect(
        MaterialLocalizations.of(tester.element(calendar)).datePickerHelpText,
        'Tarih seçin',
      );
    },
  );

  testWidgets(
    'manual customer notification stays available on a narrow phone screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.initialize();
      final today = DateTime.now();
      await store.saveCustomer(
        const CustomerModel(
          id: 'customer-manual',
          name: 'Kiracı Uzun Adı',
          email: 'tenant@example.com',
          phone: '+90 555 123 45 67',
        ),
      );
      await store.saveAdSpace(
        const AdSpaceModel(
          id: 'space-manual',
          name: 'Dar Ekranda Uzun Pano Adı',
        ),
      );
      await store.saveContract(
        ContractModel(
          id: 'contract-manual',
          customerId: 'customer-manual',
          adSpaceId: 'space-manual',
          startDate: today.subtract(const Duration(days: 30)),
          endDate: today.add(const Duration(days: 5)),
        ),
      );

      await tester.pumpWidget(RSTDolapdereApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bildirimler').first);
      await tester.pumpAndSettle();

      expect(find.text('Müşteriye e-posta'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Otomatik e-posta açık'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contracts expose filters, ended menu, and renewal actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.initialize();
    final today = DateTime.now();
    await store.saveCustomer(const CustomerModel(id: 'c1', name: 'Kiracı'));
    await store.saveAdSpace(const AdSpaceModel(id: 'a1', name: 'Pano'));
    await store.saveContract(
      ContractModel(
        id: 'contract-list',
        customerId: 'c1',
        adSpaceId: 'a1',
        startDate: today.subtract(const Duration(days: 30)),
        endDate: today.add(const Duration(days: 5)),
      ),
    );
    await tester.pumpWidget(RSTDolapdereApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sözleşmeler').first);
    await tester.pumpAndSettle();
    expect(find.text('Filtre'), findsOneWidget);
    expect(find.text('Yakın tarih önce'), findsOneWidget);

    await tester.tap(find.byTooltip('Kayıt işlemleri'));
    await tester.pumpAndSettle();
    expect(find.text('Bitti olarak işaretle'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Biten Sözleşmeler').first);
    await tester.pumpAndSettle();
    expect(find.text('Biten Sözleşmeler'), findsWidgets);
    expect(
      find.byTooltip('Görünen sözleşmeleri PDF dışa aktar'),
      findsOneWidget,
    );
  });

  test('customer reminder mail body encodes spaces as percent escapes', () {
    final uri = buildCustomerReminderEmailUri(
      email: 'tenant@example.com',
      subject: 'Sözleşme bitiş hatırlatması',
      body: 'Merhaba Kiracı,\n\nPano adı sözleşmesi sona eriyor.',
    );

    expect(uri.scheme, 'mailto');
    expect(uri.toString(), contains('%20'));
    expect(uri.toString(), isNot(contains('+')));
    expect(uri.queryParameters['body'], contains('Merhaba Kiracı'));
  });
}
