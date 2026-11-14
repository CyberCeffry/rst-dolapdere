import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/features/contracts/services/contract_pdf_service.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/contract_model.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates a PDF with embedded Turkish font and Turkish text', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.initialize();
    await store.saveCustomer(
      const CustomerModel(id: 'c1', name: 'Çağrı Öztürk'),
    );
    await store.saveAdSpace(
      const AdSpaceModel(id: 'a1', name: 'İstanbul Çarşı Panosu'),
    );
    final contract = ContractModel(
      id: 'contract-utf8',
      customerId: 'c1',
      adSpaceId: 'a1',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2027, 1, 1),
      monthlyPrice: 12500,
      responsibleUserId: 'user-1',
      responsibleUsername: 'sorumlu',
    );

    final bytes = await ContractPdfService.buildContractsPdf(store, [contract]);

    expect(String.fromCharCodes(bytes.take(8)), startsWith('%PDF-'));
    expect(bytes.length, greaterThan(5000));
  });
}
