import 'dart:async'; // Timer, Future, unawaited, TimeoutException için
import 'dart:convert'; // jsonEncode / jsonDecode için

import 'package:cloud_firestore/cloud_firestore.dart'; // Firebase veritabanı
import 'package:flutter/material.dart'; // ChangeNotifier, ThemeMode, WidgetsBindingObserver
import 'package:shared_preferences/shared_preferences.dart'; // Cihazda küçük veri saklama

import '../../models/ad_space_model.dart'; // Reklam alanı modeli
import '../../models/contract_history_entry.dart'; // Sözleşme geçmişi kaydı
import '../../models/contract_model.dart'; // Sözleşme modeli
import '../../models/reservation_model.dart';
import '../../models/customer_model.dart'; // Müşteri modeli
import '../utils/date_helper.dart'; // Tarih yardımcıları
import 'background_sync.dart'; // Android arka plan eşitleme

/// Eşitleme durumu. Arayüz bunu dinler; böylece durum değişince tüm uygulama
/// (ve bildirim yeniden planlama) tetiklenmez.
class SyncStatus {
  // Tüm alanların varsayılan değeri var; const olduğu için değişmez nesne.
  const SyncStatus({
    this.busy = false, // Şu an eşitleme çalışıyor mu
    this.error, // Son hata mesajı (yoksa null)
    this.lastSync, // Son başarılı eşitleme zamanı
    this.pending = 0, // Gönderilmeyi bekleyen değişiklik sayısı
  });

  final bool busy;
  final String? error;
  final DateTime? lastSync;
  final int pending;
}

// Uygulamanın tüm verisini tutan merkez sınıf. ChangeNotifier: değişince
// dinleyen ekranlar yenilenir. WidgetsBindingObserver: uygulamanın ön plana/
// arka plana geçişini yakalar.
class AppStore extends ChangeNotifier with WidgetsBindingObserver {
  // Özel (private) kurucu: dışarıdan değil, sadece initialize() ile üretilir.
  AppStore._(this._preferences, this._firestore, {String? initialSyncError})
    : syncError = initialSyncError {
    // Kayıtlı tema modunu oku ('light', 'dark', 'system').
    final savedThemeMode = _preferences.getString('themeMode');
    themeMode = ValueNotifier(
      ThemeMode.values.firstWhere(
        (mode) => mode.name == savedThemeMode,
        orElse: () => ThemeMode.system, // Kayıt yoksa sistem temasını kullan
      ),
    );
    // Cihazdaki kayıtlı müşteri, reklam alanı ve sözleşme listelerini yükle.
    _customers = _readList('customers', CustomerModel.fromJson);
    _adSpaces = _readList('adSpaces', AdSpaceModel.fromJson);
    _contracts = _readList('contracts', ContractModel.fromJson);
    _reservations = _readList('reservations', ReservationModel.fromJson);

    // Hatırlatma ayarlarını yükle (yoksa varsayılan değerler).
    phoneRemindersEnabled =
        _preferences.getBool('phoneRemindersEnabled') ?? true;
    windowsRemindersEnabled =
        _preferences.getBool('windowsRemindersEnabled') ?? false;
    reminderOffsets = _readReminderOffsets(); // Kaç gün önce hatırlatılacak
    workingDays = _readWorkingDays(); // Hangi günler çalışılıyor

    // Hatırlatma saati, gece yarısından itibaren dakika (540 = 09:00).
    reminderTimeMinutes = _preferences.getInt('reminderTimeMinutes') ?? 540;

    // Başlangıç eşitleme durumunu oluştur.
    syncStatus = ValueNotifier(
      SyncStatus(
        error: initialSyncError,
        lastSync: lastSuccessfulSync,
        pending: pendingChangeCount,
      ),
    );
  }

  static const _workspaceId =
      'rst_dolapdere'; // Firestore'daki çalışma alanı kimliği

  final SharedPreferences _preferences; // Yerel depolama
  final FirebaseFirestore? _firestore; // Null ise bulut eşitleme kapalı
  late final ValueNotifier<ThemeMode>
  themeMode; // Tema değişimini dinlenebilir yapar

  /// Eşitleme durumu (çalışıyor mu, hata, son eşitleme, bekleyen değişiklik).
  late final ValueNotifier<SyncStatus> syncStatus;

  // Bellekteki listeler (constructor içinde doldurulur).
  late List<CustomerModel> _customers;
  late List<AdSpaceModel> _adSpaces;
  late List<ContractModel> _contracts;
  late List<ReservationModel> _reservations;

  Timer? _syncTimer; // Periyodik eşitleme zamanlayıcısı
  Future<void> _syncLock =
      Future<void>.value(); // İşlemleri sıraya dizen "kilit"
  Future<void>?
  _fullSyncFuture; // Devam eden tam eşitleme (tekrar başlatmamak için)
  int _busyCount = 0; // Aynı anda kaç eşitleme işlemi çalışıyor

  bool phoneRemindersEnabled = true; // Telefon bildirimleri açık mı
  bool windowsRemindersEnabled = false; // Windows bildirimleri açık mı

  int reminderTimeMinutes = 540; // Hatırlatma saati (dakika cinsinden)
  List<int> reminderOffsets = [10, 5, 0]; // Bitişten kaç gün önce hatırlat
  List<int> workingDays = [1, 2, 3, 4, 5]; // 1 = Pazartesi ... 7 = Pazar

  // Seçilebilecek hatırlatma günleri.
  static const availableReminderOffsets = [30, 21, 14, 10, 7, 5, 3, 1, 0];
  // Gün numarası -> Türkçe gün adı.
  static const weekdayLabels = {
    DateTime.monday: 'Pazartesi',
    DateTime.tuesday: 'Salı',
    DateTime.wednesday: 'Çarşamba',
    DateTime.thursday: 'Perşembe',
    DateTime.friday: 'Cuma',
    DateTime.saturday: 'Cumartesi',
    DateTime.sunday: 'Pazar',
  };
  String? syncError; // Son eşitleme hatası

  // Uygulama açılışında çağrılır: store'u kurar, Firestore'u ve yaşam döngüsünü bağlar.
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
      // Beklemeden (arka planda) Firestore başlatılır.
      unawaited(store._initializeFirestore());
    }
    store._attachLifecycle(); // Ön plan/arka plan takibini başlat

    return store;
  }

  bool get cloudSyncEnabled => _firestore != null; // Bulut eşitleme var mı
  bool get isCloudSyncing => _busyCount > 0; // Şu an eşitleme yapılıyor mu

  // Tema modunu kaydet ve dinleyenlere bildir.
  Future<void> setThemeMode(ThemeMode mode) async {
    await _preferences.setString('themeMode', mode.name);
    themeMode.value = mode;
  }

  // Dışarıya değiştirilemez kopya olarak verilir; listeleri sadece store değiştirir.
  List<CustomerModel> get customers => List.unmodifiable(_customers);
  List<AdSpaceModel> get adSpaces => List.unmodifiable(_adSpaces);
  List<ContractModel> get contracts => List.unmodifiable(_contracts);
  List<ReservationModel> get reservations => List.unmodifiable(_reservations);

  /// Reklam alanı için bekleyen rezervasyon (yoksa null).
  ReservationModel? reservationForAdSpace(String adSpaceId) {
    for (final reservation in _reservations) {
      if (reservation.adSpaceId == adSpaceId) return reservation;
    }
    return null;
  }

  /// Reklam alanını rezerve eden müşterinin adı (rezervasyon yoksa null).
  String? reservedByNameFor(String adSpaceId) {
    final reservation = reservationForAdSpace(adSpaceId);
    if (reservation == null) return null;
    return customerFor(reservation.customerId)?.name ?? 'Müşteri';
  }

  // workspaces/rst_dolapdere/<name> koleksiyon referansı.
  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _firestore!.collection('workspaces').doc(_workspaceId).collection(name);

  // Hatırlatma ayarlarının tutulduğu Firestore dokümanı.
  DocumentReference<Map<String, dynamic>> get _settingsDocument => _firestore!
      .collection('workspaces')
      .doc(_workspaceId)
      .collection('settings')
      .doc('reminders');

  // Kayıtlı hatırlatma günlerini okur; geçersizse varsayılana döner.
  List<int> _readReminderOffsets() {
    final saved = _preferences.getStringList('reminderOffsets');
    if (saved == null) return [10, 5, 0];
    final values =
        saved
            .map(int.tryParse) // Metni sayıya çevir
            .whereType<int>() // Çevrilemeyenleri at
            .where(availableReminderOffsets.contains) // Geçerli değerleri tut
            .toSet() // Tekrarları kaldır
            .toList()
          ..sort((a, b) => b.compareTo(a)); // Büyükten küçüğe sırala
    return values.isEmpty ? [10, 5, 0] : values;
  }

  // Kayıtlı çalışma günlerini okur; geçersizse Pzt-Cum varsayılanı.
  List<int> _readWorkingDays() {
    final saved = _preferences.getStringList('workingDays');
    if (saved == null) return [1, 2, 3, 4, 5];
    final values =
        saved
            .map(int.tryParse)
            .whereType<int>()
            .where(weekdayLabels.containsKey) // Sadece 1-7 arası
            .toSet()
            .toList()
          ..sort(); // Küçükten büyüğe
    return values.isEmpty ? [1, 2, 3, 4, 5] : values;
  }

  // Genel liste okuyucu: JSON metnini modele çevirir. [decode] her öğeyi modele dönüştürür.
  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) decode) {
    final raw = _preferences.getString(key);

    if (raw == null) return <T>[]; // Hiç kayıt yoksa boş liste

    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => decode(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on FormatException {
      return <T>[]; // Bozuk JSON
    } on TypeError {
      return <T>[]; // Beklenmeyen veri tipi
    }
  }

  // Listeyi JSON metnine çevirip cihaza kaydeder.
  Future<void> _saveList(String key, List<dynamic> values) async {
    await _preferences.setString(
      key,
      jsonEncode(values.map((value) => value.toJson()).toList()),
    );
  }

  static const String _pendingChangesKey = 'pendingSyncChanges';

  // Firebase'e henüz gönderilmemiş değişiklikleri okur.
  List<Map<String, dynamic>> _readPendingChanges() {
    final raw = _preferences.getString(_pendingChangesKey);
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return []; // Okunamazsa boş say
    }
  }

  // Bekleyen değişiklik listesini kaydeder.
  Future<void> _savePendingChanges(List<Map<String, dynamic>> changes) async {
    await _preferences.setString(_pendingChangesKey, jsonEncode(changes));
  }

  static const String _lastSyncKey = 'lastSuccessfulSync';

  // Son başarılı eşitleme zamanı (hiç yoksa null).
  DateTime? get lastSuccessfulSync {
    final value = _preferences.getString(_lastSyncKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  // Son eşitleme zamanını UTC olarak kaydeder.
  Future<void> _saveLastSync(DateTime date) async {
    await _preferences.setString(_lastSyncKey, date.toUtc().toIso8601String());
  }

  // Bekleyen değişiklik ekler. Aynı kayıt için eski bekleyen değişikliğin yerini alır.
  Future<void> _addPendingChange({
    required String collection, // Hangi koleksiyon
    required String id, // Kaydın kimliği
    required bool deleted, // Silme işlemi mi
    Map<String, dynamic>? data, // Kaydın verisi (silmede null)
  }) async {
    final changes = _readPendingChanges();

    // Aynı kayda ait eski bekleyen değişikliği çıkar (sadece sonuncusu kalsın).
    changes.removeWhere(
      (item) => item['collection'] == collection && item['id'] == id,
    );

    changes.add({
      'collection': collection,
      'id': id,
      'deleted': deleted,
      'data': data,
      'updatedAt': DateTime.now()
          .toUtc()
          .toIso8601String(), // Çakışma çözümünde kullanılır
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

  static const _collectionNames = [
    'customers',
    'adSpaces',
    'contracts',
    'reservations',
  ]; // Eşitlenen koleksiyonlar
  static const Duration _networkTimeout = Duration(
    seconds: 20,
  ); // Ağ isteği zaman aşımı
  static const _serverOnly = GetOptions(
    source: Source.server,
  ); // Önbelleği değil sunucuyu oku

  /// 0 = otomatik eşitleme kapalı (yalnızca elle).
  static const availableSyncIntervals = [
    0,
    15,
    30,
    60,
    120,
  ]; // Dakika cinsinden
  static const String _syncIntervalKey = 'syncIntervalMinutes';

  // Seçili eşitleme aralığı (varsayılan 30 dk).
  int get syncIntervalMinutes {
    final saved = _preferences.getInt(_syncIntervalKey) ?? 30;
    return availableSyncIntervals.contains(saved) ? saved : 30;
  }

  // Eşitleme aralığını değiştirir, zamanlayıcıyı ve arka plan görevini yeniler.
  Future<void> setSyncIntervalMinutes(int minutes) async {
    if (!availableSyncIntervals.contains(minutes)) return; // Geçersizse yok say
    await _preferences.setInt(_syncIntervalKey, minutes);
    _restartSyncTimer();
    if (_firestore != null) {
      unawaited(BackgroundSync.schedule(minutes, force: true));
    }
  }

  static const String _settingsDirtyKey = 'settingsDirty';
  int _settingsRevision =
      0; // Ayar kaç kez değişti (yarış durumunu önlemek için)

  // Ayarlar değişti ama henüz gönderilmedi mi.
  bool get _settingsDirty => _preferences.getBool(_settingsDirtyKey) ?? false;

  // Bekleyen toplam değişiklik: kayıtlar + (ayar değiştiyse 1).
  int get pendingChangeCount =>
      _readPendingChanges().length + (_settingsDirty ? 1 : 0);

  static const String _instantSyncKey = 'syncInstantly';

  /// Açıksa kayıt ekleme/düzenleme/silme anında Firebase'e gönderilir.
  /// Kapalıysa (varsayılan) değişiklikler cihazda bekler; seçilen aralıkta veya
  /// "Şimdi eşitle" ile toplu gönderilir.
  bool get instantSyncEnabled => _preferences.getBool(_instantSyncKey) ?? false;

  // Anlık gönderimi aç/kapat. Açılırsa bekleyenler hemen gönderilir.
  Future<void> setInstantSyncEnabled(bool value) async {
    await _preferences.setBool(_instantSyncKey, value);
    if (value && pendingChangeCount > 0) unawaited(syncNow());
  }

  // ---------------------------------------------------------------------------
  // ARKA PLAN / ÖN PLAN
  //
  // * Android: WorkManager görevi (background_sync.dart) uygulama kapalıyken de
  //   seçilen aralıkta eşitler.
  // * Uygulama öne gelince: arka planda değişen veriler yeniden okunur ve süre
  //   dolduysa hemen eşitlenir (zamanlayıcı arka planda durmuş olabilir).
  // ---------------------------------------------------------------------------

  static const String _foregroundKey = 'appForegroundAt';

  // Yaşam döngüsü dinlemeyi başlatır ve uygulamayı "ön planda" işaretler.
  void _attachLifecycle() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_markForeground(true));
  }

  // Ön plan zamanını kaydeder/siler. Arka plan görevi bunu okuyarak çakışmayı önler.
  Future<void> _markForeground(bool value) async {
    if (value) {
      await _preferences.setString(
        _foregroundKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } else {
      await _preferences.remove(_foregroundKey);
    }
  }

  // Eşitleme zamanı geldi mi? (aralık dolduysa true)
  bool get _syncDue {
    final minutes = syncIntervalMinutes;
    if (minutes <= 0) return false; // Otomatik eşitleme kapalı
    final last = lastSuccessfulSync;
    return last == null ||
        DateTime.now().difference(last) >= Duration(minutes: minutes);
  }

  // Uygulama durumu değişince Flutter bunu çağırır.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed: // Ön plana geldi
        unawaited(_handleResumed());
      case AppLifecycleState.paused: // Arka plana gitti
      case AppLifecycleState.detached: // Kapanıyor
        unawaited(_markForeground(false));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break; // Bir şey yapma
    }
  }

  // Bellekteki liste, diskteki kayıttan farklı mı? (arka plan görevi değiştirmiş olabilir)
  bool _differs(String key, List<dynamic> current) =>
      jsonEncode(current.map((item) => item.toJson()).toList()) !=
      (_preferences.getString(key) ?? '[]');

  // Uygulama öne gelince çalışır.
  Future<void> _handleResumed() async {
    await _markForeground(true);
    if (_busyCount == 0) {
      // Eşitleme çalışmıyorsa diskten yeniden oku (arka plan değişiklikleri için).
      await _preferences.reload();
      final changed =
          _differs('customers', _customers) ||
          _differs('adSpaces', _adSpaces) ||
          _differs('contracts', _contracts) ||
          _differs('reservations', _reservations);
      if (changed) {
        _customers = _readList('customers', CustomerModel.fromJson);
        _adSpaces = _readList('adSpaces', AdSpaceModel.fromJson);
        _contracts = _readList('contracts', ContractModel.fromJson);
        _reservations = _readList('reservations', ReservationModel.fromJson);
        _publishSyncStatus();
        notifyListeners(); // Ekranları yenile
      }
    }
    _restartSyncTimer(); // Zamanlayıcı arka planda durmuş olabilir
    if (_firestore != null && _syncDue) unawaited(syncNow());
  }

  /// Android arka plan görevi için başsız (arayüzsüz) eşitleme.
  static Future<bool> runBackgroundSync(FirebaseFirestore firestore) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload(); // En güncel veriyi oku
    final foregroundAt = DateTime.tryParse(
      preferences.getString(_foregroundKey) ?? '',
    );
    if (foregroundAt != null &&
        DateTime.now().toUtc().difference(foregroundAt.toUtc()) <
            const Duration(hours: 6)) {
      // Uygulama ön planda: kendi zamanlayıcısı eşitliyor, çakışma olmasın.
      return true;
    }
    final store = AppStore._(preferences, firestore); // Geçici store
    try {
      await store.syncNow();
      return store.syncError == null; // Hata yoksa başarılı
    } finally {
      store.dispose(); // Kaynakları temizle
    }
  }

  // Periyodik eşitleme zamanlayıcısını (yeniden) kurar.
  void _restartSyncTimer() {
    _syncTimer?.cancel(); // Eskisini iptal et
    _syncTimer = null;
    final minutes = syncIntervalMinutes;
    if (_firestore == null || minutes <= 0) return; // Gerek yoksa kurma
    _syncTimer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(syncNow()),
    );
  }

  // Açılışta Firestore ile ilgili başlangıç işlemleri.
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
    if (_firestore == null) {
      return Future<void>.value(); // Bulut yoksa bir şey yapma
    }
    // ??= : devam eden eşitleme varsa onu döndür, yoksa yenisini başlat.
    return _fullSyncFuture ??= _exclusive(() => _track(_runFullSync))
        .whenComplete(() {
          _fullSyncFuture = null; // Bitince sıfırla
        });
  }

  // İşlemleri sıraya sokar: bir önceki bitmeden yenisi başlamaz.
  Future<void> _exclusive(Future<void> Function() operation) {
    final next = _syncLock.then((_) => operation());
    _syncLock = next.catchError((_) {}); // Hata sırayı bozmasın
    return next;
  }

  // İşlemi çalıştırır; meşgul sayacını ve hata durumunu yönetir.
  Future<void> _track(Future<void> Function() body) async {
    _busyCount++;
    _publishSyncStatus(); // "Çalışıyor" durumunu yayınla
    try {
      await body();
      syncError = null; // Başarılı: hatayı temizle
    } on TimeoutException {
      syncError =
          'Sunucuya ulaşılamadı (zaman aşımı). İnternet bağlantısını kontrol edin.';
    } catch (error) {
      syncError = error.toString();
    } finally {
      _busyCount--;
      _publishSyncStatus(); // Son durumu yayınla
    }
  }

  // Güncel eşitleme durumunu arayüze bildirir.
  void _publishSyncStatus() {
    syncStatus.value = SyncStatus(
      busy: _busyCount > 0,
      error: syncError,
      lastSync: lastSuccessfulSync,
      pending: pendingChangeCount,
    );
  }

  // Ağ isteğine zaman aşımı ekler.
  Future<T> _net<T>(Future<T> future) => future.timeout(_networkTimeout);

  // Tam eşitleme: tüm koleksiyonlar + ayarlar.
  Future<void> _runFullSync() async {
    final startedAt =
        DateTime.now(); // Eşitleme başlangıç zamanı (sonraki "since" için)
    var dataChanged = false;

    for (final name in _collectionNames) {
      if (await _syncCollection(name)) dataChanged = true;
    }
    // Veri değiştiyse reklam alanlarının boş/dolu durumunu yeniden hesapla.
    if (dataChanged) await _refreshAvailability();

    final settingsChanged = await _syncSettings();

    await _saveLastSync(startedAt);
    if (dataChanged || settingsChanged) notifyListeners();
  }

  // Hatırlatma ayarlarını eşitler. Ayar yerelde değiştiyse true/false döner.
  Future<bool> _syncSettings() async {
    if (_settingsDirty) {
      // Cihazdaki ayar değişmişse önce o gönderilir (sunucudakiyle ezilmez).
      await _pushSettingsNow();
      return false;
    }
    final settings = await _net(_settingsDocument.get(_serverOnly));
    if (settings.exists) {
      return _applySettings(settings.data() ?? {}); // Sunucudaki ayarı uygula
    }
    // Sunucuda hiç ayar yoksa yereldekini yükle.
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
            onlyIds: {id}, // Sadece bu kayıt
            pull: false, // Sunucudan veri çekme
          );
          if (changed) {
            await _refreshAvailability();
            notifyListeners();
          }
        }),
      ),
    );
  }

  // Metni tarihe çevirir; olmazsa 1970 (en eski tarih) döner.
  DateTime _readTime(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  // İsme göre ilgili yerel listeyi verir.
  List<dynamic> _listFor(String name) => switch (name) {
    'customers' => _customers,
    'adSpaces' => _adSpaces,
    'reservations' => _reservations,
    _ => _contracts,
  };

  // İsme göre yerel listeyi yenisiyle değiştirir.
  void _assignList(String name, List<dynamic> items) {
    switch (name) {
      case 'customers':
        _customers = items.cast<CustomerModel>().toList();
      case 'adSpaces':
        _adSpaces = items.cast<AdSpaceModel>().toList();
      case 'reservations':
        _reservations = items.cast<ReservationModel>().toList();
      default:
        _contracts = items.cast<ContractModel>().toList();
    }
  }

  // JSON'u ilgili modele çevirir.
  dynamic _decode(String name, Map<String, dynamic> json) => switch (name) {
    'customers' => CustomerModel.fromJson(json),
    'adSpaces' => AdSpaceModel.fromJson(json),
    'reservations' => ReservationModel.fromJson(json),
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
    final collection = _collection(name); // Asıl veri koleksiyonu
    final tombstones = _collection(
      '_sync_deletions',
    ); // Silinenlerin izi ("mezar taşı")
    final lastSync = lastSuccessfulSync;

    // Bu koleksiyona ait (ve varsa istenen kimliklere ait) bekleyen değişiklikler.
    final changes = _readPendingChanges()
        .where(
          (item) =>
              item['collection'] == name &&
              (onlyIds == null || onlyIds.contains(item['id'])),
        )
        .toList();

    // Yerel kayıtlar: id -> model haritası.
    final values = <String, dynamic>{
      for (final item in _listFor(name)) (item as dynamic).id as String: item,
    };
    final pushed = <String>{}; // Sunucuya gönderilen kimlikler
    var changed = false; // Yerel liste değişti mi

    // 1) Bekleyen yerel değişiklikleri gönder.
    for (final change in changes) {
      final id = change['id'] as String;
      final localTime = _readTime(
        change['updatedAt'],
      ); // Yerel değişiklik zamanı
      final remoteRef = collection.doc(id);
      final deletedRef = tombstones.doc('${name}_$id');

      // Sunucudaki kaydı ve silinme izini aynı anda sorgula.
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
          values.remove(id); // Sunucuda silinmiş: yerelden de sil
        } else if (remote.exists) {
          values[id] = _decode(name, {
            ...remote.data()!,
            'id': id,
          }); // Sunucu sürümünü al
        }
        changed = true;
      } else {
        // Yerel değişiklik daha yeni: sunucuya yaz.
        final write = _firestore!.batch(); // Toplu (atomik) yazma
        if (change['deleted'] == true) {
          // Silme: iz bırak + kaydı sil.
          write.set(deletedRef, {
            'collection': name,
            'recordId': id,
            '_syncUpdatedAt': localTime.toIso8601String(),
          });
          write.delete(remoteRef);
          values.remove(id);
        } else {
          // Ekleme/düzenleme: kaydı yaz + varsa silinme izini kaldır.
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
      await _clearPending(change); // Bekleyen listesinden çıkar
    }

    // 2) Son eşitlemeden beri sunucuda değişenleri çek (yalnızca tam eşitleme).
    if (pull) {
      final since = lastSync?.toUtc().toIso8601String();
      // Not: Tek alanlı sorgular indeks gerektirmez. Silinenlerde 'collection'
      // ve '_syncUpdatedAt' birlikte sorgulanırsa bileşik indeks gerekir; bu
      // yüzden tarihe göre çekip koleksiyona göre uygulamada süzüyoruz.
      Query<Map<String, dynamic>> docsQuery = collection; // Varsayılan: hepsi
      Query<Map<String, dynamic>> deletesQuery = tombstones.where(
        'collection',
        isEqualTo: name,
      );
      if (since != null) {
        // Daha önce eşitlenmişse sadece yeni değişenleri iste.
        docsQuery = collection.where('_syncUpdatedAt', isGreaterThan: since);
        deletesQuery = tombstones.where('_syncUpdatedAt', isGreaterThan: since);
      }

      // Değişen kayıtları ve silinenleri aynı anda çek.
      final results = await Future.wait([
        _net(docsQuery.get(_serverOnly)),
        _net(deletesQuery.get(_serverOnly)),
      ]);
      final docs = results[0];
      final deletes = results[1];

      // Silinenler: recordId -> silinme zamanı (sadece bu koleksiyonunkiler).
      final deletedAt = <String, DateTime>{
        for (final doc in deletes.docs)
          if (doc.data()['collection'] == name &&
              doc.data()['recordId'] is String)
            doc.data()['recordId'] as String: _readTime(
              doc.data()['_syncUpdatedAt'],
            ),
      };

      final seen = <String>{}; // İşlenen kayıt kimlikleri
      for (final doc in docs.docs) {
        final id = doc.id;
        seen.add(id);
        if (pushed.contains(id)) continue; // Az önce biz gönderdik, atla
        final docTime = _readTime(doc.data()['_syncUpdatedAt']);
        final deletedTime = deletedAt[id];
        if (deletedTime != null && !deletedTime.isBefore(docTime)) {
          // Silinme, kaydın güncellenmesinden yeni: yerelden sil.
          if (values.remove(id) != null) changed = true;
        } else {
          // Sunucudaki kaydı yerele al/güncelle.
          values[id] = _decode(name, {...doc.data(), 'id': id});
          changed = true;
        }
      }
      // Sadece silinmiş olup docs içinde görünmeyen kayıtları da yerelden sil.
      for (final entry in deletedAt.entries) {
        if (seen.contains(entry.key) || pushed.contains(entry.key)) continue;
        if (values.remove(entry.key) != null) changed = true;
      }
    }

    if (changed) {
      // Değişiklik varsa belleğe ve diske yaz.
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

  // Kayıtları diske yazar, bekleyen değişikliğe ekler ve (anlık açıksa) gönderir.
  Future<void> _persistCollection(String name, List<dynamic> values) async {
    await _saveList(name, _listFor(name)); // Tüm listeyi kaydet

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

  // Silmeyi bekleyen değişiklik olarak ekler ve (anlık açıksa) gönderir.
  Future<void> _deleteRemote(String name, String id) async {
    await _addPendingChange(collection: name, id: id, deleted: true);
    _pushRecord(name, id);
  }

  // Hatırlatma ayarlarının JSON hali (Firebase'e gönderilir).
  Map<String, dynamic> get _settingsJson => {
    'phoneRemindersEnabled': phoneRemindersEnabled,
    'windowsRemindersEnabled': windowsRemindersEnabled,
    'reminderTimeMinutes': reminderTimeMinutes,
    'reminderOffsets': reminderOffsets,
    'workingDays': workingDays,
  };

  // Sunucudan gelen ayarları uygular. Bir şey değiştiyse true döner.
  Future<bool> _applySettings(Map<String, dynamic> values) async {
    final before = jsonEncode(_settingsJson); // Karşılaştırma için eski hali
    // Değer yoksa mevcut değeri koru (??).
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

    if (jsonEncode(_settingsJson) == before) return false; // Değişiklik yok

    // Değişen ayarları cihaza kaydet.
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
    _settingsRevision++; // Değişiklik sayacını artır
    await _preferences.setBool(_settingsDirtyKey, true);
    if (_firestore == null) return;
    if (instantSyncEnabled) {
      await _exclusive(() => _track(_pushSettingsNow));
    } else {
      _publishSyncStatus(); // Sadece "bekleyen" sayısını güncelle
    }
  }

  // Ayarları hemen Firebase'e gönderir.
  Future<void> _pushSettingsNow() async {
    final revision = _settingsRevision; // Gönderim başındaki sürüm
    await _net(
      _settingsDocument.set({
        ..._settingsJson,
        'updatedAt': FieldValue.serverTimestamp(), // Sunucu saati
      }, SetOptions(merge: true)), // Mevcut dokümanla birleştir
    );
    // Gönderirken ayar tekrar değiştiyse işaret kalkmaz.
    if (revision == _settingsRevision) {
      await _preferences.setBool(_settingsDirtyKey, false);
    }
  }

  // Müşteri ekle/güncelle.
  Future<void> saveCustomer(CustomerModel customer) async {
    _customers = _upsert(
      _customers,
      customer,
      (item) => item.id,
    ); // Varsa güncelle, yoksa ekle

    await _persistCollection('customers', [customer]);
    notifyListeners();
  }

  // Müşteri sil (bağlı sözleşme varsa engeller).
  Future<void> deleteCustomer(String id) async {
    if (_contracts.any((contract) => contract.customerId == id)) {
      throw StateError(
        'Bu müşteriye bağlı sözleşmeler var. Önce sözleşmeleri silin.',
      );
    }

    if (_reservations.any((item) => item.customerId == id)) {
      throw StateError(
        'Bu müşteriye ait rezervasyon var. Önce rezervasyonu silin.',
      );
    }

    _customers.removeWhere((customer) => customer.id == id);

    await _saveList('customers', _customers);

    unawaited(_deleteRemote('customers', id)); // Silmeyi sunucuya bildir

    notifyListeners();
  }

  // Reklam alanı ekle/güncelle.
  Future<void> saveAdSpace(AdSpaceModel adSpace) async {
    _adSpaces = _upsert(_adSpaces, adSpace, (item) => item.id);

    await _persistCollection('adSpaces', [adSpace]);
    notifyListeners();
  }

  // Reklam alanı sil (aktif sözleşmesi varsa engeller).
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

    if (_reservations.any((item) => item.adSpaceId == id)) {
      throw StateError(
        'Bu reklam alanı için rezervasyon var. Önce rezervasyonu silin.',
      );
    }

    _adSpaces.removeWhere((space) => space.id == id);

    await _saveList('adSpaces', _adSpaces);

    unawaited(_deleteRemote('adSpaces', id));

    notifyListeners();
  }

  // Rezervasyon ekle/güncelle (reklam alanı başına tek rezervasyon).
  Future<void> saveReservation(ReservationModel reservation) async {
    if (!_adSpaces.any((space) => space.id == reservation.adSpaceId)) {
      throw StateError('Reklam alanı bulunamadı.');
    }
    if (!_customers.any((customer) => customer.id == reservation.customerId)) {
      throw StateError('Müşteri bulunamadı.');
    }
    if (_reservations.any(
      (item) =>
          item.id != reservation.id && item.adSpaceId == reservation.adSpaceId,
    )) {
      throw StateError(
        'Bu reklam alanı için zaten bir rezervasyon var. '
        'Önce mevcut rezervasyonu düzenleyin veya silin.',
      );
    }
    _reservations = _upsert(_reservations, reservation, (item) => item.id);
    await _persistCollection('reservations', [reservation]);
    notifyListeners();
  }

  // Rezervasyon sil.
  Future<void> deleteReservation(String id) async {
    _reservations.removeWhere((item) => item.id == id);
    await _saveList('reservations', _reservations);
    unawaited(_deleteRemote('reservations', id));
    notifyListeners();
  }

  // Sözleşme sil.
  Future<void> deleteContract(String id) async {
    _contracts.removeWhere((contract) => contract.id == id);

    await _saveList('contracts', _contracts);

    unawaited(_deleteRemote('contracts', id));

    await _refreshAvailability(); // Alan tekrar boşa çıkmış olabilir
    notifyListeners();
  }

  // Sözleşme ekle/güncelle (doğrulamalarla).
  Future<void> saveContract(ContractModel contract) async {
    final existing = _contracts.where((item) => item.id == contract.id);
    final existingContract = existing.firstOrNull; // Varsa mevcut sürüm

    // Bitmiş sözleşme yeniden düzenlenemez.
    if (existing.isNotEmpty &&
        (existing.first.isFinalized ||
            DateHelper.daysUntil(existing.first.endDate) < 0)) {
      throw StateError(
        'Biten sözleşme yeniden açılamaz. Devam etmek için Uzat seçeneğini kullanın.',
      );
    }

    // Aynı alanda tarihleri çakışan başka aktif sözleşme var mı?
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

    // Kaydedilecek sözleşmeyi oluştur (eksik alanları mevcut sürümden tamamla).
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
      pdfPath: contract.pdfPath,
      // Mevcut geçmiş korunur; yeni sözleşmeyse "oluşturuldu" kaydı eklenir.
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

  // Sözleşmeyi sonlandırır (kapatır).
  Future<void> markContractEnded(String id) async {
    final index = _contracts.indexWhere((item) => item.id == id);

    if (index < 0) {
      throw StateError('Sözleşme bulunamadı.');
    }

    final current = _contracts[index];

    if (current.isFinalized) return; // Zaten bitmiş

    final finalized = _copyContract(
      current,
      isActive: false,
      isFinalized: true,
      finalizedAt: DateTime.now(),
      history: [
        ...current.history, // Eski geçmiş
        ContractHistoryEntry(
          action: ContractHistoryAction.ended, // "Sonlandırıldı" kaydı
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

    // Uzatma aynı müşteri ve aynı alan için olmalı.
    if (source.customerId != renewed.customerId ||
        source.adSpaceId != renewed.adSpaceId) {
      throw StateError(
        'Sözleşme aynı müşteri ve reklam alanı için uzatılmalıdır.',
      );
    }

    // Aynı sözleşme güncellenir: başlangıç aynı, bitiş/fiyat/süre yeni.
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
      isActive: true, // Uzatılınca tekrar aktif
      isFinalized: false,
      finalizedAt: null,
      renewedFromContractId: source.renewedFromContractId,
      responsibleUserId: source.responsibleUserId,
      responsibleUsername: source.responsibleUsername,
      pdfPath: renewed.pdfPath,
      history: [
        ...source.history,
        ContractHistoryEntry(
          action: ContractHistoryAction.renewed, // "Uzatıldı" kaydı
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

  // Hatırlatma ayarlarını doğrulayıp kaydeder.
  Future<void> saveReminderSettings({
    required bool phone,
    bool? windows,
    int? reminderMinutes,
    List<int>? reminderOffsets,
    List<int>? workingDays,
  }) async {
    List<int>? selectedOffsets;
    if (reminderOffsets != null) {
      // Geçerli günleri süz, tekrarları kaldır, büyükten küçüğe sırala.
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

    // Bellekteki değerleri güncelle (verilmeyenler aynen kalır).
    phoneRemindersEnabled = phone;
    windowsRemindersEnabled = windows ?? windowsRemindersEnabled;

    reminderTimeMinutes = reminderMinutes ?? reminderTimeMinutes;
    if (selectedOffsets != null) this.reminderOffsets = selectedOffsets;
    if (selectedWorkingDays != null) this.workingDays = selectedWorkingDays;

    // Cihaza kaydet.
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

    unawaited(_markSettingsDirty()); // Sunucuya gönderilmek üzere işaretle

    notifyListeners(); // Bildirimler yeniden planlansın
  }

  // Kimliğe göre müşteri bul (yoksa null).
  CustomerModel? customerFor(String id) {
    for (final customer in _customers) {
      if (customer.id == id) return customer;
    }

    return null;
  }

  // Kimliğe göre reklam alanı bul (yoksa null).
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

  // Sözleşmeyi aktif/pasif yapar ve geçmişe kaydeder.
  Future<void> setContractActive(String id, bool isActive) async {
    final index = _contracts.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Sözleşme bulunamadı.');
    final source = _contracts[index];
    final now = DateTime.now();
    final updated = _copyContract(
      source,
      isActive: isActive,
      isFinalized: !isActive, // Pasif yapmak = sonlandırmak
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

  // Bugün geçerli olan sözleşmeler: aktif, sonlanmamış, başlamış ve bitmemiş.
  List<ContractModel> get activeContracts {
    final today = DateTime.now();

    return _contracts.where((item) {
      return item.isActive &&
          !item.isFinalized &&
          DateHelper.isOnOrBeforeToday(item.startDate, today: today) &&
          DateHelper.isOnOrAfterToday(item.endDate, today: today);
    }).toList();
  }

  // Biten sözleşmeler (sonlandırılmış ya da tarihi geçmiş), en yeni bitiş önce.
  List<ContractModel> get endedContracts => _contracts.where((item) {
    return item.isFinalized || DateHelper.daysUntil(item.endDate) < 0;
  }).toList()..sort((a, b) => b.endDate.compareTo(a.endDate));

  // Bitişine 10 gün veya daha az kalan aktif sözleşmeler, en yakın önce.
  List<ContractModel> get expiringContracts => activeContracts.where((item) {
    final days = DateHelper.daysUntil(item.endDate);
    return days >= 0 && days <= 10;
  }).toList()..sort((a, b) => a.endDate.compareTo(b.endDate));

  // Listede aynı id varsa değiştirir, yoksa ekler (kopya liste döner).
  List<T> _upsert<T>(List<T> items, T value, String Function(T) idOf) {
    final result = List<T>.of(items);

    final index = result.indexWhere((item) => idOf(item) == idOf(value));

    if (index < 0) {
      result.add(value); // Yeni kayıt
    } else {
      result[index] = value; // Mevcut kaydı güncelle
    }

    return result;
  }

  // Sözleşmenin kopyasını oluşturur; verilen alanları değiştirir, diğerlerini korur.
  ContractModel _copyContract(
    ContractModel source, {
    bool? isActive,
    bool? isFinalized,
    DateTime? finalizedAt,
    String? renewedFromContractId,
    List<ContractHistoryEntry>? history,
    String? responsibleUserId,
    String? responsibleUsername,
    String? pdfPath,
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
      pdfPath: pdfPath ?? source.pdfPath,
    );
  }

  // Her reklam alanının boş/dolu durumunu sözleşmelere göre yeniden hesaplar.
  Future<void> _refreshAvailability() async {
    final now = DateTime.now();

    _adSpaces = _adSpaces.map((space) {
      // Bu alanda bugün geçerli bir sözleşme var mı?
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
        isAvailable: !occupied, // Sözleşme yoksa müsait
      );
    }).toList();

    await _saveList('adSpaces', _adSpaces);
  }

  // Store kapanırken kaynakları serbest bırakır.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    ); // Yaşam döngüsü dinlemeyi bırak
    _syncTimer?.cancel(); // Zamanlayıcıyı durdur
    themeMode.dispose();
    syncStatus.dispose();

    super.dispose();
  }
}
