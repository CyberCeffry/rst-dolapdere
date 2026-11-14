import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/features/records/management_screens.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  testWidgets('day and month inputs keep both digits while typing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.initialize();
    await store.saveCustomer(
      const CustomerModel(id: 'customer-1', name: 'Kiracı'),
    );
    await store.saveAdSpace(const AdSpaceModel(id: 'space-1', name: 'Pano 1'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagementScreen(store: store, type: RecordType.contracts),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni Ekle'));
    await tester.pumpAndSettle();

    for (final hint in ['GG', 'AA']) {
      final field = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.hintText == hint,
          )
          .first;
      await tester.ensureVisible(field);
      await tester.enterText(field, '1');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '1');

      await tester.enterText(field, '15');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '15');
    }
  });
}
