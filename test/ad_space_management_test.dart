import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/core/theme/app_colors.dart';
import 'package:dere_sozlesme_takip/core/utils/contract_remaining_time.dart';
import 'package:dere_sozlesme_takip/features/records/management_screens.dart';
import 'package:dere_sozlesme_takip/features/records/services/ad_space_pdf_service.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/contract_model.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'remaining time uses year, month, and day units with urgency threshold',
    () {
      expect(ContractRemainingTime.format(366), '1 yıl');
      expect(ContractRemainingTime.format(365), '12 ay');
      expect(ContractRemainingTime.format(29), '29 gün');
      expect(ContractRemainingTime.isUrgent(14), isTrue);
      expect(ContractRemainingTime.isUrgent(15), isFalse);
    },
  );

  testWidgets('ad space status filter shows only matching spaces', (
    tester,
  ) async {
    final store = await _createStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagementScreen(store: store, type: RecordType.adSpaces),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dolu Pano'), findsOneWidget);
    expect(find.text('Boş Pano'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Kiracı: Ayşe'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(DropdownButtonFormField<AdSpaceListFilter>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kirada').last);
    await tester.pumpAndSettle();

    expect(find.text('Dolu Pano'), findsOneWidget);
    expect(find.text('Boş Pano'), findsNothing);

    final remainingText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere(
          (widget) => widget.text.toPlainText().contains('Kalan süre:'),
        );
    final durationSpan = _textSpans(
      remainingText.text,
    ).firstWhere((span) => span.text?.endsWith(' gün') ?? false);
    expect(durationSpan.style?.color, AppColors.danger);
  });

  test('ad space PDF builds from the supplied filtered records', () async {
    final store = await _createStore();
    final availableSpace = store.adSpaces.singleWhere(
      (space) => space.id == 'space-empty',
    );
    final bytes = await AdSpacePdfService.buildAdSpacesPdf(store, [
      availableSpace,
    ]);

    expect(String.fromCharCodes(bytes.take(8)), startsWith('%PDF-'));
    expect(bytes.length, greaterThan(3000));
  });
}

Future<AppStore> _createStore() async {
  final store = await AppStore.initialize();
  final today = DateTime.now();
  await store.saveCustomer(const CustomerModel(id: 'customer-1', name: 'Ayşe'));
  await store.saveAdSpace(
    const AdSpaceModel(id: 'space-occupied', name: 'Dolu Pano'),
  );
  await store.saveAdSpace(
    const AdSpaceModel(id: 'space-empty', name: 'Boş Pano'),
  );
  await store.saveContract(
    ContractModel(
      id: 'contract-1',
      customerId: 'customer-1',
      adSpaceId: 'space-occupied',
      startDate: today.subtract(const Duration(days: 30)),
      endDate: today.add(const Duration(days: 10)),
      responsibleUserId: 'user-1',
      responsibleUsername: 'Ayşe Sorumlu',
    ),
  );
  return store;
}

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _textSpans(child);
  }
}
