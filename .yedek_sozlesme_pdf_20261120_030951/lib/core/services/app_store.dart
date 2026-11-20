import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ad_space_model.dart';
import '../../models/contract_history_entry.dart';
import '../../models/contract_model.dart';
import '../../models/customer_model.dart';
import '../utils/date_helper.dart';

/// Eşitleme durumu. Arayüz bunu dinler; böylece durum değişince tüm uygulama
/// (ve bildirim yeniden planlama) tetiklenmez.
class SyncStatus {
  const SyncStatus({
    this.busy = false,
    this.error,
    this.lastSync,
    this.pending = 0,
  });

  final bool busy;
  final String? error;
  final DateTime? lastSync;
  final int pending;
}

class AppStore extends ChangeNotifier {
  AppStore._(this._preferences, this._firestore, {String? initialSyncError})
    : syncError = initialSyncError {
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

    syncStatus = ValueNotifier(
      SyncStatus(
        error: initialSyncError,
        lastSync: lastSuccessfulSync,
        pending: pendingChangeCount,
      ),
    );
  }

  static const _workspaceId = 'rst_dolapdere';

  final SharedPreferences _preferences;
  final FirebaseFirestore? _firestore;
  late final ValueNotifier<ThemeMode> themeMode;

  /// Eşitleme durumu (çalışıyor mu, hata, son eşitleme, bekleyen değişiklik).
  late final ValueNotifier<SyncStatus> syncStatus;

  late List<CustomerModel> _customers;
  late List<AdSpaceModel> _adSpaces;
  late List<ContractModel> _contracts;

  Timer? _syncTimer;
  Future<void> _syncLock = Future<void>.value();
  Future<void>? _fullSyncFuture;
  int _busyCount = 0;

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
    String? initialSyncError,
  }) async {
    final store = AppStore._(
      await SharedPreferences.getInstance(),
      firestore,
      initialSyncError: initialSyncError,
    );

    if (firestore != null) {
      unawaited(store._initializeFirestore());
    }

    return store;
  }

  bool get cloudSyncEnabled => _firestore != null;
  bool get isCloudSyncing => _busyCount > 0;

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

  static const String _pendingChangesKey = 'pendingSyncChanges';

  List<Map<String, dynamic>> _readPendingChanges() {
    final raw = _preferences.getString(_pendingChangesKey);
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePendingChanges(List<Map<String, dynamic>> changes) async {
    await _preferences.setString(_pendingChangesKey, jsonEncode(changes));
  }

  static const String _lastSyncKey = 'lastSuccessfulSync';

  DateTime? get lastSuccessfulSync {
    final value = _preferences.getString(_lastSyncKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> _saveLastSync(DateTime date) async {
    await _preferences.setString(_lastSyncKey, date.toUtc().toIso8601String());
  }

  Future<void> _addPendingChange({
    required String collection,
    required String id,
    required bool deleted,
    Map<String, dynamic>? data,
  }) async {
    final changes = _readPendingChanges();

    changes.removeWhere(
      (item) => item['collection'] == collection && item['id'] == id,
    );

    changes.add({
      'collection': collection,
      'id': id,
      'deleted': deleted,
      'data': data,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    await _savePendingChanges(changes);
  }

  // ---------------------------------------------------------------------------
  // EŞİTLEME
  //
  // * Canlı dinleyici (snapshots) YOKTUR.
  // * Kayıt ekleme / düzenleme / silme: yalnızca o kayıt Firebase'e gönderilir.
  // * Tam eşitleme (gönder + yeni değişiklikleri çek): açılışta, seçilen
  //   aralıkta (Ayarlar > Firebase) ve "Şimdi eşitle" butonuna basınca.
  // * Eşitleme işlemleri sırayla çalışır; birbirinin üstüne binmez.
  // ---------------------------------------------------------------------------

  static const _collectionNames = ['customers', 'adSpaces', 'contracts'];
  static const Duration _networkTimeout = Duration(seconds: 20);
  static const _serverOnly = GetOptions(source: Source.server);

  /// 0 = otomatik eşitleme kapalı (yalnızca elle).
  static const availableSyncIntervals = [0, 15, 30, 60, 120];
  static const String _syncIntervalKey = 'syncIntervalMinutes';

  int get syncIntervalMinutes {
    final saved = _preferences.getInt(_syncIntervalKey) ?? 30;
    return availableSyncIntervals.contains(saved) ? saved : 30;
  }

  Future<void> setSyncIntervalMinutes(int minutes) async {
    if (!availableSyncIntervals.contains(minutes)) return;
    await _preferences.setInt(_syncIntervalKey, minutes);
    _restartSyncTimer();
  }

  static const String _settingsDirtyKey = 'settingsDirty';
  int _settingsRevision = 0;

  bool get _settingsDirty => _preferences.getBool(_settingsDirtyKey) ?? false;

  int get pendingChangeCount =>
      _readPendingChanges().length + (_settingsDirty ? 1 : 0);

  static const String _instantSyncKey = 'syncInstantly';

  /// Açıksa kayıt ekleme/düzenleme/silme anında Firebase'e gönderilir.
  /// Kapalıysa (varsayılan) değişiklikler cihazda bekler; seçilen aralıkta veya
  /// "Şimdi eşitle" ile toplu gönderilir.
  bool get instantSyncEnabled =>
      _preferences.getBool(_instantSyncKey) ?? false;

  Future<void> setInstantSyncEnabled(bool value) async {
    await _preferences.setBool(_instantSyncKey, value);
    if (value && pendingChangeCount > 0) unawaited(syncNow());
  }

  void _restartSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
    final minutes = syncIntervalMinutes;
    if (_firestore == null || minutes <= 0) return;
    _syncTimer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(syncNow()),
    );
  }

  Future<void> _initializeFirestore() async {
    _restartSyncTimer();
    // Açılışta her seferinde eşitleme yapılmaz: son eşitlemenin üzerinden seçilen
    // süre geçmediyse beklenir (kontrolü zamanlayıcı yapar). İlk kurulumda
    // (hiç eşitleme yoksa) bir kez eşitlenir.
    final last = lastSuccessfulSync;
    final minutes = syncIntervalMinutes;
    final due =
        last == null ||
        (minutes > 0 &&
            DateTime.now().difference(last) >= Duration(minutes: minutes));
    if (due) await syncNow();
  }

  /// Tam eşitleme. Zaten çalışıyorsa aynı işlemi bekler, ikinci kez başlatmaz.
  Future<void> syncNow() {
    if (_firestore == null) return Future<void>.value();
    return _fullSyncFuture ??= _exclusive(() => _track(_runFullSync))
        .whenComplete(() {
          _fullSyncFuture = null;
        });
  }

  Future<void> _exclusive(Future<void> Function() operation) {
    final next = _syncLock.then((_) => operation());
    _syncLock = next.catchError((_) {});
    return next;
  }

  Future<void> _track(Future<void> Function() body) async {
    _busyCount++;
    _publishSyncStatus();
    try {
      await body();
      syncError = null;
    } on TimeoutException {
      syncError =
          'Sunucuya ulaşılamadı (zaman aşımı). İnternet bağlantısını kontrol edin.';
    } catch (error) {
      syncError = error.toString();
    } finally {
      _busyCount--;
      _publishSyncStatus();
    }
  }

  void _publishSyncStatus() {
    syncStatus.value = SyncStatus(
      busy: _busyCount > 0,
      error: syncError,
      lastSync: lastSuccessfulSync,
      pending: pendingChangeCount,
    );
  }

  Future<T> _net<T>(Future<T> future) => future.timeout(_networkTimeout);

  Future<void> _runFullSync() async {
    final startedAt = DateTime.now();
    var dataChanged = false;

    for (final name in _collectionNames) {
      if (await _syncCollection(name)) dataChanged = true;
    }
    if (dataChanged) await _refreshAvailability();

    final settingsChanged = await _syncSettings();

    await _saveLastSync(startedAt);
    if (dataChanged || settingsChanged) notifyListeners();
  }

  Future<bool> _syncSettings() async {
    if (_settingsDirty) {
      // Cihazdaki ayar değişmişse önce o gönderilir (sunucudakiyle ezilmez).
      await _pushSettingsNow();
      return false;
    }
    final settings = await _net(_settingsDocument.get(_serverOnly));
    if (settings.exists) {
      return _applySettings(settings.data() ?? {});
    }
    await _net(
      _settingsDocument.set({
        ..._settingsJson,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return false;
  }

  /// Yerelde değişen tek bir kaydı Firebase'e gönderir (başka veri çekmez).
  void _pushRecord(String name, String id) {
    if (_firestore == null) return;
    if (!instantSyncEnabled) {
      // Değişiklik bekleyenler listesinde kalır; sonraki eşitlemede gider.
      _publishSyncStatus();
      return;
    }
    unawaited(
      _exclusive(
        () => _track(() async {
          final changed = await _syncCollection(
            name,
            onlyIds: {id},
            pull: false,
          );
          if (changed) {
            await _refreshAvailability();
            notifyListeners();
          }
        }),
      ),
    );
  }

  DateTime _readTime(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  List<dynamic> _listFor(String name) => switch (name) {
    'customers' => _customers,
    'adSpaces' => _adSpaces,
    _ => _contracts,
  };

  void _assignList(String name, List<dynamic> items) {
    switch (name) {
      case 'customers':
        _customers = items.cast<CustomerModel>().toList();
      case 'adSpaces':
        _adSpaces = items.cast<AdSpaceModel>().toList();
      default:
        _contracts = items.cast<ContractModel>().toList();
    }
  }

  dynamic _decode(String name, Map<String, dynamic> json) => switch (name) {
    'customers' => CustomerModel.fromJson(json),
    'adSpaces' => AdSpaceModel.fromJson(json),
    _ => ContractModel.fromJson(json),
  };

  /// Bir koleksiyonu eşitler.
  /// [onlyIds] verilirse yalnızca bu kayıtların bekleyen değişiklikleri gönderilir.
  /// [pull] false ise sunucudan yeni kayıt çekilmez.
  /// Yerel liste değiştiyse true döner.
  Future<bool> _syncCollection(
    String name, {
    Set<String>? onlyIds,
    bool pull = true,
  }) async {
    final collection = _collection(name);
    final tombstones = _collection('_sync_deletions');
    final lastSync = lastSuccessfulSync;

    final changes = _readPendingChanges()
        .where(
          (item) =>
              item['collection'] == name &&
              (onlyIds == null || onlyIds.contains(item['id'])),
        )
        .toList();

    final values = <String, dynamic>{
      for (final item in _listFor(name)) (item as dynamic).id as String: item,
    };
    final pushed = <String>{};
    var changed = false;

    // 1) Bekleyen yerel değişiklikleri gönder.
    for (final change in changes) {
      final id = change['id'] as String;
      final localTime = _readTime(change['updatedAt']);
      final remoteRef = collection.doc(id);
      final deletedRef = tombstones.doc('${name}_$id');

      final snapshots = await Future.wait([
        _net(remoteRef.get(_serverOnly)),
        _net(deletedRef.get(_serverOnly)),
      ]);
      final remote = snapshots[0];
      final remoteDeleted = snapshots[1];
      final remoteTime = _readTime(remote.data()?['_syncUpdatedAt']);
      final deletedTime = _readTime(remoteDeleted.data()?['_syncUpdatedAt']);

      if (remoteTime.isAfter(localTime) || deletedTime.isAfter(localTime)) {
        // Sunucudaki sürüm daha yeni: yerel değişiklik bırakılır.
        if (deletedTime.isAfter(remoteTime)) {
          values.remove(id);
        } else if (remote.exists) {
          values[id] = _decode(name, {...remote.data()!, 'id': id});
        }
        changed = true;
      } else {
        final write = _firestore!.batch();
        if (change['deleted'] == true) {
          write.set(deletedRef, {
            'collection': name,
            'recordId': id,
            '_syncUpdatedAt': localTime.toIso8601String(),
          });
          write.delete(remoteRef);
          values.remove(id);
        } else {
          final data = Map<String, dynamic>.from(change['data'] as Map);
          write.set(remoteRef, {
            ...data,
            '_syncUpdatedAt': localTime.toIso8601String(),
          });
          write.delete(deletedRef);
        }
        await _net(write.commit());
        pushed.add(id);
      }
      await _clearPending(change);
    }

    // 2) Son eşitlemeden beri sunucuda değişenleri çek (yalnızca tam eşitleme).
    if (pull) {
      final since = lastSync?.toUtc().toIso8601String();
      // Not: Tek alanlı sorgular indeks gerektirmez. Silinenlerde 'collection'
      // ve '_syncUpdatedAt' birlikte sorgulanırsa bileşik indeks gerekir; bu
      // yüzden tarihe göre çekip koleksiyona göre uygulamada süzüyoruz.
      Query<Map<String, dynamic>> docsQuery = collection;
      Query<Map<String, dynamic>> deletesQuery = tombstones.where(
        'collection',
        isEqualTo: name,
      );
      if (since != null) {
        docsQuery = collection.where('_syncUpdatedAt', isGreaterThan: since);
        deletesQuery = tombstones.where(
          '_syncUpdatedAt',
          isGreaterThan: since,
        );
      }

      final results = await Future.wait([
        _net(docsQuery.get(_serverOnly)),
        _net(deletesQuery.get(_serverOnly)),
      ]);
      final docs = results[0];
      final deletes = results[1];

      final deletedAt = <String, DateTime>{
        for (final doc in deletes.docs)
          if (doc.data()['collection'] == name &&
              doc.data()['recordId'] is String)
            doc.data()['recordId'] as String: _readTime(
              doc.data()['_syncUpdatedAt'],
            ),
      };

      final seen = <String>{};
      for (final doc in docs.docs) {
        final id = doc.id;
        seen.add(id);
        if (pushed.contains(id)) continue;
        final docTime = _readTime(doc.data()['_syncUpdatedAt']);
        final deletedTime = deletedAt[id];
        if (deletedTime != null && !deletedTime.isBefore(docTime)) {
          if (values.remove(id) != null) changed = true;
        } else {
          values[id] = _decode(name, {...doc.data(), 'id': id});
          changed = true;
        }
      }
      for (final entry in deletedAt.entries) {
        if (seen.contains(entry.key) || pushed.contains(entry.key)) continue;
        if (values.remove(entry.key) != null) changed = true;
      }
    }

    if (changed) {
      final list = values.values.toList();
      _assignList(name, list);
      await _saveList(name, list);
    }
    return changed;
  }

  /// Gönderilen bekleyen değişikliği listeden çıkarır. Aynı kayıt arada tekrar
  /// düzenlendiyse (updatedAt farklı) yeni değişiklik korunur.
  Future<void> _clearPending(Map<String, dynamic> done) async {
    final current = _readPendingChanges();
    current.removeWhere(
      (item) =>
          item['collection'] == done['collection'] &&
          item['id'] == done['id'] &&
          item['updatedAt'] == done['updatedAt'],
    );
    await _savePendingChanges(current);
  }

  Future<void> _persistCollection(String name, List<dynamic> values) async {
    await _saveList(name, _listFor(name));

    for (final value in values) {
      final id = value.id as String;
      await _addPendingChange(
        collection: name,
        id: id,
        deleted: false,
        data: value.toJson() as Map<String, dynamic>,
      );
      _pushRecord(name, id);
    }
  }

  Future<void> _deleteRemote(String name, String id) async {
    await _addPendingChange(collection: name, id: id, deleted: true);
    _pushRecord(name, id);
  }

  Map<String, dynamic> get _settingsJson => {
    'phoneRemindersEnabled': phoneRemindersEnabled,
    'windowsRemindersEnabled': windowsRemindersEnabled,
    'reminderTimeMinutes': reminderTimeMinutes,
    'reminderOffsets': reminderOffsets,
    'workingDays': workingDays,
  };

  Future<bool> _applySettings(Map<String, dynamic> values) async {
    final before = jsonEncode(_settingsJson);
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

    if (jsonEncode(_settingsJson) == before) return false;

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
    return true;
  }

  /// Ayar değiştiğinde yalnızca işaretlenir. Anlık gönderme kapalıysa
  /// (varsayılan) Firebase'e bir sonraki eşitlemede gider.
  Future<void> _markSettingsDirty() async {
    _settingsRevision++;
    await _preferences.setBool(_settingsDirtyKey, true);
    if (_firestore == null) return;
    if (instantSyncEnabled) {
      await _exclusive(() => _track(_pushSettingsNow));
    } else {
      _publishSyncStatus();
    }
  }

  Future<void> _pushSettingsNow() async {
    final revision = _settingsRevision;
    await _net(
      _settingsDocument.set({
        ..._settingsJson,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
    // Gönderirken ayar tekrar değiştiyse işaret kalkmaz.
    if (revision == _settingsRevision) {
      await _preferences.setBool(_settingsDirtyKey, false);
    }
  }

  Future<void> saveCustomer(CustomerModel customer) async {
    _customers = _upsert(_customers, customer, (item) => item.id);

    await _persistCollection('customers', [customer]);
    notifyListeners();
  }

  Future<void> deleteCustomer(String id) async {
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
    _adSpaces = _upsert(_adSpaces, adSpace, (item) => item.id);

    await _persistCollection('adSpaces', [adSpace]);
    notifyListeners();
  }

  Future<void> deleteAdSpace(String id) async {
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
    _contracts.removeWhere((contract) => contract.id == id);

    await _saveList('contracts', _contracts);

    unawaited(_deleteRemote('contracts', id));

    await _refreshAvailability();
    notifyListeners();
  }

  Future<void> saveContract(ContractModel contract) async {
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

    unawaited(_markSettingsDirty());

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

  Future<void> setContractActive(String id, bool isActive) async {
    final index = _contracts.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Sözleşme bulunamadı.');
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
        ),
      ],
    );
    _contracts[index] = updated;
    await _persistCollection('contracts', [updated]);
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
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    themeMode.dispose();
    syncStatus.dispose();

    super.dispose();
  }
}
