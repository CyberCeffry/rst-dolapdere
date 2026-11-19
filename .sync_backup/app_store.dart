import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ad_space_model.dart';
import '../../models/app_user.dart';
import '../../models/contract_history_entry.dart';
import '../../models/contract_model.dart';
import '../../models/customer_model.dart';
import 'auth_service.dart';
import '../utils/date_helper.dart';

class AppStore extends ChangeNotifier {
  AppStore._(
    this._preferences,
    this._firestore,
    this._user, {
    String? initialSyncError,
  }) : syncError = initialSyncError {
    final savedThemeMode = _preferences.getString('themeMode');
    themeMode = ValueNotifier(
      ThemeMode.values.firstWhere(
        (mode) => mode.name == savedThemeMode,
        orElse: () => ThemeMode.system,
      ),
    );
    _customers = _readList('customers', CustomerModel.fromJson);
    _adSpaces = _readList('adSpaces', AdSpaceModel.fromJson);
    _contracts = _readList('contracts', ContractModel.fromJson);

    phoneRemindersEnabled =
        _preferences.getBool('phoneRemindersEnabled') ?? true;
    windowsRemindersEnabled =
        _preferences.getBool('windowsRemindersEnabled') ?? false;
    reminderOffsets = _readReminderOffsets();
    workingDays = _readWorkingDays();

    reminderTimeMinutes = _preferences.getInt('reminderTimeMinutes') ?? 540;
  }

  static const _workspaceId = 'rst_dolapdere';

  final SharedPreferences _preferences;
  final FirebaseFirestore? _firestore;
  final AppUser? _user;
  late final ValueNotifier<ThemeMode> themeMode;
  AuthService? _authServiceInstance;

  AuthService get _authService =>
      _authServiceInstance ??= AuthService(firestore: _firestore);
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  late List<CustomerModel> _customers;
  late List<AdSpaceModel> _adSpaces;
  late List<ContractModel> _contracts;

  Future<void> _writeQueue = Future<void>.value();

  bool _isSyncing = false;

  bool phoneRemindersEnabled = true;
  bool windowsRemindersEnabled = false;

  int reminderTimeMinutes = 540;
  List<int> reminderOffsets = [10, 5, 0];
  List<int> workingDays = [1, 2, 3, 4, 5];

  static const availableReminderOffsets = [30, 21, 14, 10, 7, 5, 3, 1, 0];
  static const weekdayLabels = {
    DateTime.monday: 'Pazartesi',
    DateTime.tuesday: 'Salı',
    DateTime.wednesday: 'Çarşamba',
    DateTime.thursday: 'Perşembe',
    DateTime.friday: 'Cuma',
    DateTime.saturday: 'Cumartesi',
    DateTime.sunday: 'Pazar',
  };
  String? syncError;

  static Future<AppStore> initialize({
    FirebaseFirestore? firestore,
    AppUser? user,
    String? initialSyncError,
  }) async {
    final store = AppStore._(
      await SharedPreferences.getInstance(),
      firestore,
      user,
      initialSyncError: initialSyncError,
    );

    if (firestore != null) {
      unawaited(store._initializeFirestore());
    }

    return store;
  }

  bool get cloudSyncEnabled => _firestore != null;
  bool get isCloudSyncing => _isSyncing;
  AppUser? get currentUser => _user;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _preferences.setString('themeMode', mode.name);
    themeMode.value = mode;
  }

  List<CustomerModel> get customers => List.unmodifiable(_customers);
  List<AdSpaceModel> get adSpaces => List.unmodifiable(_adSpaces);
  List<ContractModel> get contracts => List.unmodifiable(_contracts);

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _firestore!.collection('workspaces').doc(_workspaceId).collection(name);

  DocumentReference<Map<String, dynamic>> get _settingsDocument => _firestore!
      .collection('workspaces')
      .doc(_workspaceId)
      .collection('settings')
      .doc('reminders');

  List<int> _readReminderOffsets() {
    final saved = _preferences.getStringList('reminderOffsets');
    if (saved == null) return [10, 5, 0];
    final values =
        saved
            .map(int.tryParse)
            .whereType<int>()
            .where(availableReminderOffsets.contains)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return values.isEmpty ? [10, 5, 0] : values;
  }

  List<int> _readWorkingDays() {
    final saved = _preferences.getStringList('workingDays');
    if (saved == null) return [1, 2, 3, 4, 5];
    final values =
        saved
            .map(int.tryParse)
            .whereType<int>()
            .where(weekdayLabels.containsKey)
            .toSet()
            .toList()
          ..sort();
    return values.isEmpty ? [1, 2, 3, 4, 5] : values;
  }

  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) decode) {
    final raw = _preferences.getString(key);

    if (raw == null) return <T>[];

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => decode(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on FormatException {
      return <T>[];
    } on TypeError {
      return <T>[];
    }
  }

  Future<void> _saveList(String key, List<dynamic> values) async {
    await _preferences.setString(
      key,
      jsonEncode(values.map((value) => value.toJson()).toList()),
    );
  }

  Future<void> _initializeFirestore() async {
    _isSyncing = true;
    notifyListeners();

    try {
      await Future.wait([
        _mergeCollection<CustomerModel>(
          name: 'customers',
          local: () => _customers,
          decode: CustomerModel.fromJson,
          idOf: (item) => item.id,
          assign: (items) => _customers = items,
        ),
        _mergeCollection<AdSpaceModel>(
          name: 'adSpaces',
          local: () => _adSpaces,
          decode: AdSpaceModel.fromJson,
          idOf: (item) => item.id,
          assign: (items) => _adSpaces = items,
        ),
        _mergeCollection<ContractModel>(
          name: 'contracts',
          local: () => _contracts,
          decode: ContractModel.fromJson,
          idOf: (item) => item.id,
          assign: (items) => _contracts = items,
        ),
      ]);

      if (_user?.role != AppRole.supervisor) {
        final settings = await _settingsDocument.get();
        if (settings.exists) {
          await _applySettings(settings.data() ?? {});
        } else {
          await _writeCloudSettings();
        }
      }

      syncError = null;
    } catch (error) {
      syncError = error.toString();
    } finally {
      _listenCollection<CustomerModel>(
        'customers',
        CustomerModel.fromJson,
        (items) => _customers = items,
      );

      _listenCollection<AdSpaceModel>(
        'adSpaces',
        AdSpaceModel.fromJson,
        (items) => _adSpaces = items,
      );

      _listenCollection<ContractModel>(
        'contracts',
        ContractModel.fromJson,
        (items) => _contracts = items,
      );

      if (_user?.role != AppRole.supervisor) {
        _subscriptions.add(
          _settingsDocument.snapshots().listen((snapshot) {
            if (snapshot.exists) {
              unawaited(_applySettings(snapshot.data() ?? {}));
            }
          }, onError: _setSyncError),
        );
      }

      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _mergeCollection<T>({
    required String name,
    required List<T> Function() local,
    required T Function(Map<String, dynamic>) decode,
    required String Function(T) idOf,
    required void Function(List<T>) assign,
  }) async {
    final collection = _collection(name);
    final snapshot = await _queryCollection(name).get();

    final merged = <String, T>{
      if (_user?.role != AppRole.supervisor)
        for (final item in local()) idOf(item): item,
    };

    final remoteIds = <String>{};

    for (final document in snapshot.docs) {
      merged[document.id] = decode({...document.data(), 'id': document.id});

      remoteIds.add(document.id);
    }

    final values = merged.values.toList();

    assign(values);
    await _saveList(name, values);

    if (_user?.role == AppRole.supervisor) return;
    final missing = merged.entries.where(
      (entry) => !remoteIds.contains(entry.key),
    );

    for (final entry in missing) {
      unawaited(
        _writeDocument(
          collection.doc(entry.key),
          (entry.value as dynamic).toJson(),
        ),
      );
    }
  }

  void _listenCollection<T>(
    String name,
    T Function(Map<String, dynamic>) decode,
    void Function(List<T>) assign,
  ) {
    _subscriptions.add(
      _queryCollection(name).snapshots().listen((snapshot) {
        if (snapshot.metadata.isFromCache) return;

        try {
          final values = snapshot.docs
              .map(
                (document) => decode({...document.data(), 'id': document.id}),
              )
              .toList();

          assign(values);

          unawaited(_saveList(name, values));

          if (name == 'contracts') {
            unawaited(_refreshAvailability());
          }

          syncError = null;
          notifyListeners();
        } catch (error) {
          _setSyncError(error);
        }
      }, onError: _setSyncError),
    );
  }

  Query<Map<String, dynamic>> _queryCollection(String name) {
    final collection = _collection(name);
    if (_user?.role != AppRole.supervisor) return collection;
    if (name == 'contracts') {
      return collection.where('responsibleUserId', isEqualTo: _user!.uid);
    }
    final ids = name == 'customers'
        ? _user!.assignedCustomerIds
        : name == 'adSpaces'
        ? _user!.assignedAdSpaceIds
        : const <String>[];
    if (ids.isEmpty) {
      return collection.where(
        FieldPath.documentId,
        isEqualTo: '__no_assigned_records__',
      );
    }
    return collection.where(
      FieldPath.documentId,
      whereIn: ids.take(30).toList(),
    );
  }

  Future<void> _writeDocument(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> data,
  ) => _queue(() => reference.set(data));

  Future<void> _writeCollection(String name, List<dynamic> values) async {
    final collection = _collection(name);

    for (var start = 0; start < values.length; start += 450) {
      final batch = _firestore!.batch();

      for (final value in values.skip(start).take(450)) {
        batch.set(
          collection.doc(value.id as String),
          value.toJson() as Map<String, dynamic>,
        );
      }

      await batch.commit();
    }
  }

  Future<void> _queue(Future<void> Function() operation) {
    final next = _writeQueue.then((_) async {
      if (_firestore == null) return;

      _isSyncing = true;
      notifyListeners();

      try {
        await operation();
        syncError = null;
      } catch (error) {
        _setSyncError(error);
      } finally {
        _isSyncing = false;
        notifyListeners();
      }
    });

    _writeQueue = next.catchError((_) {});

    return next;
  }

  Future<void> _persistCollection(String name, List<dynamic> values) async {
    await _saveList(
      name,
      name == 'customers'
          ? _customers
          : name == 'adSpaces'
          ? _adSpaces
          : _contracts,
    );

    if (_firestore != null) {
      unawaited(_queue(() => _writeCollection(name, values)));
    }
  }

  Future<void> _deleteRemote(String name, String id) async {
    if (_firestore == null) return;

    await _queue(() => _collection(name).doc(id).delete());
  }

  Map<String, dynamic> get _settingsJson => {
    'phoneRemindersEnabled': phoneRemindersEnabled,
    'windowsRemindersEnabled': windowsRemindersEnabled,
    'reminderTimeMinutes': reminderTimeMinutes,
    'reminderOffsets': reminderOffsets,
    'workingDays': workingDays,
  };

  Future<void> _applySettings(Map<String, dynamic> values) async {
    phoneRemindersEnabled =
        values['phoneRemindersEnabled'] as bool? ?? phoneRemindersEnabled;

    windowsRemindersEnabled =
        values['windowsRemindersEnabled'] as bool? ?? windowsRemindersEnabled;

    reminderTimeMinutes =
        (values['reminderTimeMinutes'] as num?)?.toInt() ?? reminderTimeMinutes;
    final configuredOffsets = values['reminderOffsets'];
    if (configuredOffsets is List) {
      final parsedOffsets =
          configuredOffsets
              .whereType<num>()
              .map((value) => value.toInt())
              .where(availableReminderOffsets.contains)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      if (parsedOffsets.isNotEmpty) reminderOffsets = parsedOffsets;
    }

    final configuredWorkingDays = values['workingDays'];
    if (configuredWorkingDays is List) {
      final parsedDays =
          configuredWorkingDays
              .whereType<num>()
              .map((value) => value.toInt())
              .where(weekdayLabels.containsKey)
              .toSet()
              .toList()
            ..sort();
      if (parsedDays.isNotEmpty) workingDays = parsedDays;
    }

    await _preferences.setBool('phoneRemindersEnabled', phoneRemindersEnabled);
    await _preferences.setBool(
      'windowsRemindersEnabled',
      windowsRemindersEnabled,
    );

    await _preferences.setInt('reminderTimeMinutes', reminderTimeMinutes);
    await _preferences.setStringList(
      'reminderOffsets',
      reminderOffsets.map((offset) => offset.toString()).toList(),
    );
    await _preferences.setStringList(
      'workingDays',
      workingDays.map((weekday) => weekday.toString()).toList(),
    );
    notifyListeners();
  }

  Future<void> _writeCloudSettings() async {
    if (_firestore == null) return;

    await _queue(
      () => _settingsDocument.set({
        ..._settingsJson,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  void _setSyncError(Object error) {
    syncError = error.toString();
    _isSyncing = false;
    notifyListeners();
  }

  Future<void> saveCustomer(CustomerModel customer) async {
    if (_user?.role == AppRole.supervisor) {
      throw StateError('Sorumlu kiracı ekleyemez veya düzenleyemez.');
    }
    _customers = _upsert(_customers, customer, (item) => item.id);

    await _persistCollection('customers', [customer]);
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
    if (_user?.role == AppRole.supervisor) {
      throw StateError('Sorumlu kiracı silemez.');
    }
    if (_contracts.any((contract) => contract.customerId == id)) {
      throw StateError(
        'Bu müşteriye bağlı sözleşmeler var. Önce sözleşmeleri silin.',
      );
    }

    _customers.removeWhere((customer) => customer.id == id);

    await _saveList('customers', _customers);

    unawaited(_deleteRemote('customers', id));

    notifyListeners();
  }

  Future<void> saveAdSpace(AdSpaceModel adSpace) async {
    if (_user?.role == AppRole.supervisor) {
      throw StateError('Sorumlu reklam alanı ekleyemez veya düzenleyemez.');
    }
    _adSpaces = _upsert(_adSpaces, adSpace, (item) => item.id);

    await _persistCollection('adSpaces', [adSpace]);
    notifyListeners();
  }

  Future<void> deleteAdSpace(String id) async {
    if (_user?.role == AppRole.supervisor) {
      throw StateError('Sorumlu reklam alanı silemez.');
    }
    if (_contracts.any(
      (contract) =>
          contract.adSpaceId == id &&
          contract.isActive &&
          !contract.isFinalized,
    )) {
      throw StateError(
        'Bu alanda aktif sözleşme var. Önce sözleşmeyi sonlandırın.',
      );
    }

    _adSpaces.removeWhere((space) => space.id == id);

    await _saveList('adSpaces', _adSpaces);

    unawaited(_deleteRemote('adSpaces', id));

    notifyListeners();
  }

  Future<void> deleteContract(String id) async {
    if (_user?.role == AppRole.supervisor) {
      throw StateError('Sorumlu sözleşme silemez.');
    }
    _contracts.removeWhere((contract) => contract.id == id);

    await _saveList('contracts', _contracts);

    unawaited(_deleteRemote('contracts', id));

    await _refreshAvailability();
    notifyListeners();
  }

  Future<void> saveContract(ContractModel contract) async {
    if (_user?.role == AppRole.supervisor) {
      await _authService.submitContractChange(
        operation: 'create',
        contract: contract,
      );
      return;
    }
    final existing = _contracts.where((item) => item.id == contract.id);
    final existingContract = existing.firstOrNull;

    if (existing.isNotEmpty &&
        (existing.first.isFinalized ||
            DateHelper.daysUntil(existing.first.endDate) < 0)) {
      throw StateError(
        'Biten sözleşme yeniden açılamaz. Devam etmek için Uzat seçeneğini kullanın.',
      );
    }

    final overlaps = _contracts.any(
      (item) =>
          item.id != contract.id &&
          item.adSpaceId == contract.adSpaceId &&
          item.isActive &&
          !item.isFinalized &&
          !DateHelper.daysUntil(
            item.endDate,
            from: contract.startDate,
          ).isNegative &&
          !DateHelper.daysUntil(
            contract.endDate,
            from: item.startDate,
          ).isNegative,
    );

    if (contract.isActive && overlaps) {
      throw StateError('Bu reklam alanında devam eden başka bir sözleşme var.');
    }

    final savedContract = ContractModel(
      id: contract.id,
      customerId: contract.customerId,
      adSpaceId: contract.adSpaceId,
      startDate: contract.startDate,
      endDate: contract.endDate,
      monthlyPrice: contract.monthlyPrice,
      durationUnit: contract.durationUnit,
      durationCount: contract.durationCount,
      notes: contract.notes,
      isActive: contract.isActive,
      isFinalized: contract.isFinalized,
      finalizedAt: contract.finalizedAt,
      renewedFromContractId: contract.renewedFromContractId,
      responsibleUserId:
          contract.responsibleUserId ??
          existingContract?.responsibleUserId ??
          '',
      responsibleUsername:
          contract.responsibleUsername ?? existingContract?.responsibleUsername,
      history:
          existingContract?.history ??
          [
            ContractHistoryEntry(
              action: ContractHistoryAction.created,
              occurredAt: DateTime.now(),
              newEndDate: contract.endDate,
              newMonthlyPrice: contract.monthlyPrice,
              actorUid: _user?.uid,
              actorUsername: _user?.username,
            ),
          ],
    );

    _contracts = _upsert(_contracts, savedContract, (item) => item.id);

    await _persistCollection('contracts', [savedContract]);
    await _refreshAvailability();

    notifyListeners();
  }

  Future<void> markContractEnded(String id) async {
    final index = _contracts.indexWhere((item) => item.id == id);

    if (index < 0) {
      throw StateError('Sözleşme bulunamadı.');
    }

    final current = _contracts[index];

    if (_user?.role == AppRole.supervisor) {
      await _authService.setContractActive(contractId: id, isActive: false);
      await setContractActive(id, false, alreadyUpdatedRemotely: true);
      return;
    }

    if (current.isFinalized) return;

    final finalized = _copyContract(
      current,
      isActive: false,
      isFinalized: true,
      finalizedAt: DateTime.now(),
      history: [
        ...current.history,
        ContractHistoryEntry(
          action: ContractHistoryAction.ended,
          occurredAt: DateTime.now(),
          previousEndDate: current.endDate,
          newEndDate: current.endDate,
          previousMonthlyPrice: current.monthlyPrice,
          newMonthlyPrice: current.monthlyPrice,
          actorUid: _user?.uid,
          actorUsername: _user?.username,
        ),
      ],
    );

    _contracts[index] = finalized;

    await _persistCollection('contracts', [finalized]);
    await _refreshAvailability();

    notifyListeners();
  }

  // SÖZLEŞME UZATMA
  Future<void> renewContract(String sourceId, ContractModel renewed) async {
    final index = _contracts.indexWhere((item) => item.id == sourceId);

    if (index < 0) {
      throw StateError('Uzatılacak sözleşme bulunamadı.');
    }

    final source = _contracts[index];

    if (_user?.role == AppRole.supervisor) {
      await _authService.submitContractChange(
        operation: 'renew',
        contractId: sourceId,
        contract: renewed,
      );
      return;
    }

    if (source.customerId != renewed.customerId ||
        source.adSpaceId != renewed.adSpaceId) {
      throw StateError(
        'Sözleşme aynı müşteri ve reklam alanı için uzatılmalıdır.',
      );
    }

    final updated = ContractModel(
      id: source.id,
      customerId: source.customerId,
      adSpaceId: source.adSpaceId,
      startDate: source.startDate,
      endDate: renewed.endDate,
      monthlyPrice: renewed.monthlyPrice,
      durationUnit: renewed.durationUnit,
      durationCount: renewed.durationCount,
      notes: renewed.notes,
      isActive: true,
      isFinalized: false,
      finalizedAt: null,
      renewedFromContractId: source.renewedFromContractId,
      responsibleUserId: source.responsibleUserId,
      responsibleUsername: source.responsibleUsername,
      history: [
        ...source.history,
        ContractHistoryEntry(
          action: ContractHistoryAction.renewed,
          occurredAt: DateTime.now(),
          previousEndDate: source.endDate,
          newEndDate: renewed.endDate,
          previousMonthlyPrice: source.monthlyPrice,
          newMonthlyPrice: renewed.monthlyPrice,
          actorUid: _user?.uid,
          actorUsername: _user?.username,
        ),
      ],
    );

    _contracts[index] = updated;

    await _persistCollection('contracts', [updated]);

    await _refreshAvailability();
    notifyListeners();
  }

  Future<void> saveReminderSettings({
    required bool phone,
    bool? windows,
    int? reminderMinutes,
    List<int>? reminderOffsets,
    List<int>? workingDays,
  }) async {
    List<int>? selectedOffsets;
    if (reminderOffsets != null) {
      selectedOffsets =
          reminderOffsets
              .where(availableReminderOffsets.contains)
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      if (selectedOffsets.isEmpty) {
        throw ArgumentError.value(
          reminderOffsets,
          'reminderOffsets',
          'At least one valid reminder day must be selected.',
        );
      }
    }
    List<int>? selectedWorkingDays;
    if (workingDays != null) {
      selectedWorkingDays =
          workingDays.where(weekdayLabels.containsKey).toSet().toList()..sort();
      if (selectedWorkingDays.isEmpty) {
        throw ArgumentError.value(
          workingDays,
          'workingDays',
          'At least one valid weekday must be selected.',
        );
      }
    }

    phoneRemindersEnabled = phone;
    windowsRemindersEnabled = windows ?? windowsRemindersEnabled;

    reminderTimeMinutes = reminderMinutes ?? reminderTimeMinutes;
    if (selectedOffsets != null) this.reminderOffsets = selectedOffsets;
    if (selectedWorkingDays != null) this.workingDays = selectedWorkingDays;

    await _preferences.setBool('phoneRemindersEnabled', phone);
    await _preferences.setBool(
      'windowsRemindersEnabled',
      windowsRemindersEnabled,
    );

    await _preferences.setInt('reminderTimeMinutes', reminderTimeMinutes);
    await _preferences.setStringList(
      'reminderOffsets',
      this.reminderOffsets.map((offset) => offset.toString()).toList(),
    );
    await _preferences.setStringList(
      'workingDays',
      this.workingDays.map((weekday) => weekday.toString()).toList(),
    );

    unawaited(_writeCloudSettings());

    notifyListeners();
  }

  CustomerModel? customerFor(String id) {
    for (final customer in _customers) {
      if (customer.id == id) return customer;
    }

    return null;
  }

  AdSpaceModel? adSpaceFor(String id) {
    for (final space in _adSpaces) {
      if (space.id == id) return space;
    }

    return null;
  }

  // Müşterinin aktif sözleşme sayısı için kullanılabilir.
  int activeContractCountForCustomer(String customerId) {
    return activeContracts
        .where((contract) => contract.customerId == customerId)
        .length;
  }

  Future<void> setContractActive(
    String id,
    bool isActive, {
    bool alreadyUpdatedRemotely = false,
  }) async {
    final index = _contracts.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Sözleşme bulunamadı.');
    if (_user?.role == AppRole.supervisor && !alreadyUpdatedRemotely) {
      await _authService.setContractActive(contractId: id, isActive: isActive);
    }
    final source = _contracts[index];
    final now = DateTime.now();
    final updated = _copyContract(
      source,
      isActive: isActive,
      isFinalized: !isActive,
      finalizedAt: isActive ? null : now,
      history: [
        ...source.history,
        ContractHistoryEntry(
          action: isActive
              ? ContractHistoryAction.activated
              : ContractHistoryAction.ended,
          occurredAt: now,
          previousEndDate: source.endDate,
          newEndDate: source.endDate,
          previousMonthlyPrice: source.monthlyPrice,
          newMonthlyPrice: source.monthlyPrice,
          actorUid: _user?.uid,
          actorUsername: _user?.username,
        ),
      ],
    );
    _contracts[index] = updated;
    if (_user?.role == AppRole.supervisor) {
      await _saveList('contracts', _contracts);
    } else {
      await _persistCollection('contracts', [updated]);
    }
    await _refreshAvailability();
    notifyListeners();
  }

  // Reklam alanının aktif sözleşmesi.
  ContractModel? activeContractForAdSpace(String adSpaceId) {
    for (final contract in activeContracts) {
      if (contract.adSpaceId == adSpaceId) {
        return contract;
      }
    }

    return null;
  }

  List<ContractModel> get activeContracts {
    final today = DateTime.now();

    return _contracts.where((item) {
      return item.isActive &&
          !item.isFinalized &&
          DateHelper.isOnOrBeforeToday(item.startDate, today: today) &&
          DateHelper.isOnOrAfterToday(item.endDate, today: today);
    }).toList();
  }

  List<ContractModel> get endedContracts => _contracts.where((item) {
    return item.isFinalized || DateHelper.daysUntil(item.endDate) < 0;
  }).toList()..sort((a, b) => b.endDate.compareTo(a.endDate));

  List<ContractModel> get expiringContracts => activeContracts.where((item) {
    final days = DateHelper.daysUntil(item.endDate);
    return days >= 0 && days <= 10;
  }).toList()..sort((a, b) => a.endDate.compareTo(b.endDate));

  List<T> _upsert<T>(List<T> items, T value, String Function(T) idOf) {
    final result = List<T>.of(items);

    final index = result.indexWhere((item) => idOf(item) == idOf(value));

    if (index < 0) {
      result.add(value);
    } else {
      result[index] = value;
    }

    return result;
  }

  ContractModel _copyContract(
    ContractModel source, {
    bool? isActive,
    bool? isFinalized,
    DateTime? finalizedAt,
    String? renewedFromContractId,
    List<ContractHistoryEntry>? history,
    String? responsibleUserId,
    String? responsibleUsername,
  }) {
    return ContractModel(
      id: source.id,
      customerId: source.customerId,
      adSpaceId: source.adSpaceId,
      startDate: source.startDate,
      endDate: source.endDate,
      monthlyPrice: source.monthlyPrice,
      durationUnit: source.durationUnit,
      durationCount: source.durationCount,
      notes: source.notes,
      isActive: isActive ?? source.isActive,
      isFinalized: isFinalized ?? source.isFinalized,
      finalizedAt: finalizedAt ?? source.finalizedAt,
      renewedFromContractId:
          renewedFromContractId ?? source.renewedFromContractId,
      history: history ?? source.history,
      responsibleUserId: responsibleUserId ?? source.responsibleUserId,
      responsibleUsername: responsibleUsername ?? source.responsibleUsername,
    );
  }

  Future<void> _refreshAvailability() async {
    if (_user?.role == AppRole.supervisor) return;
    final now = DateTime.now();

    _adSpaces = _adSpaces.map((space) {
      final occupied = _contracts.any(
        (contract) =>
            contract.adSpaceId == space.id &&
            contract.isActive &&
            !contract.isFinalized &&
            DateHelper.isOnOrBeforeToday(contract.startDate, today: now) &&
            DateHelper.isOnOrAfterToday(contract.endDate, today: now),
      );

      return AdSpaceModel(
        id: space.id,
        name: space.name,
        location: space.location,
        description: space.description,
        monthlyPrice: space.monthlyPrice,
        isAvailable: !occupied,
      );
    }).toList();

    await _saveList('adSpaces', _adSpaces);

    if (_firestore != null) {
      unawaited(_queue(() => _writeCollection('adSpaces', _adSpaces)));
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    themeMode.dispose();

    super.dispose();
  }
}
