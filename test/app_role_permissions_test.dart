import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dere_sozlesme_takip/core/services/app_store.dart';
import 'package:dere_sozlesme_takip/models/ad_space_model.dart';
import 'package:dere_sozlesme_takip/models/app_user.dart';
import 'package:dere_sozlesme_takip/models/customer_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('supervisor permissions are module-scoped', () {
    const user = AppUser(
      uid: 'user-1',
      username: 'sorumlu',
      role: AppRole.supervisor,
      isActive: true,
      permissions: {'contracts': true, 'customers': false},
    );

    expect(user.canAccess('contracts'), isTrue);
    expect(user.canAccess('customers'), isFalse);
    expect(user.canAccess('settings'), isFalse);
  });

  test('supervisor cannot create tenant or ad-space records locally', () async {
    const user = AppUser(
      uid: 'user-1',
      username: 'sorumlu',
      role: AppRole.supervisor,
      isActive: true,
      assignedContractIds: ['contract-1'],
    );
    final store = await AppStore.initialize(user: user);

    await expectLater(
      store.saveCustomer(const CustomerModel(id: 'c1', name: 'Kiracı')),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      store.saveAdSpace(const AdSpaceModel(id: 'a1', name: 'Pano')),
      throwsA(isA<StateError>()),
    );
  });
}
