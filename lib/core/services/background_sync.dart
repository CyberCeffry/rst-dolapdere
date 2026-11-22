import 'dart:io';  // Platform.isAndroid kontrolü için

import 'package:cloud_firestore/cloud_firestore.dart';  // Firestore sınıfları
import 'package:firebase_core/firebase_core.dart';  // Firebase başlatma
import 'package:flutter/foundation.dart';  // kIsWeb ve debugPrint
import 'package:flutter/widgets.dart';  // WidgetsFlutterBinding için
import 'package:shared_preferences/shared_preferences.dart';  // Cihazda küçük ayar saklama
import 'package:workmanager/workmanager.dart';  // Android WorkManager (arka plan görevleri)

import '../../firebase_options.dart';  // Firebase proje anahtarları
import 'app_store.dart';  // Eşitlemeyi yürüten veri deposu

const String _uniqueName = 'rst_periodic_sync';  // Görevin benzersiz adı (iptal/yenileme için)
const String _taskName = 'rst_periodic_sync_task';  // WorkManager'a bildirilen görev adı
const String _scheduledKey = 'bgSyncScheduledMinutes';  // Son planlanan aralığın saklandığı anahtar

/// Android arka plan görevi (WorkManager) giriş noktası.
@pragma('vm:entry-point')  // Derleyici bu fonksiyonu silmesin; arka planda çağrılacak
void backgroundSyncDispatcher() {  // Arka plan görevinin giriş fonksiyonu
  Workmanager().executeTask((task, inputData) async {  // Görev tetiklenince çalışacak kodu kaydet
    try {  // Hata olursa görev çökmesin
      WidgetsFlutterBinding.ensureInitialized();  // Arayüzsüz ortamda Flutter motorunu hazırla
      if (Firebase.apps.isEmpty) {  // Firebase henüz başlatılmadıysa
        await Firebase.initializeApp(  // Firebase'i başlat
          options: DefaultFirebaseOptions.currentPlatform,  // Platforma uygun ayarlar
        );
      }
      final firestore = FirebaseFirestore.instance;  // Firestore örneğini al
      try {  // Hata olursa görev çökmesin
        firestore.settings = const Settings(persistenceEnabled: false);  // Yerel önbelleği kapat
      } catch (_) {}  // Ayar zaten yapılmışsa oluşan hatayı yoksay
      return await AppStore.runBackgroundSync(firestore);  // Başsız eşitlemeyi çalıştır; başarı durumunu WorkManager'a döndür
    } catch (error) {  // Beklenmeyen hata
      debugPrint('Arka plan eşitleme hatası: $error');  // Hatayı konsola yaz
      return false;  // Başarısız say (WorkManager tekrar deneyebilir)
    }
  });
}

/// Uygulama kapalıyken / arka plandayken de seçilen süreye göre eşitleme.
/// Yalnızca Android'de çalışır (WorkManager en az 15 dakika destekler).
/// Windows'ta uygulama açık olduğu sürece mevcut zamanlayıcı çalışır.
class BackgroundSync {  // Arka plan eşitlemesini planlayan sınıf
  static bool get supported => !kIsWeb && Platform.isAndroid;  // Yalnızca Android'de desteklenir
  static bool _initialized = false;  // WorkManager bir kez başlatılsın diye bayrak

  static Future<void> schedule(int minutes, {bool force = false}) async {  // Periyodik görevi kurar; minutes=0 kapatır
    if (!supported) return;  // Android değilse hiçbir şey yapma
    try {  // Hata olursa görev çökmesin
      final preferences = await SharedPreferences.getInstance();  // Cihaz ayarlarına eriş
      if (!force && preferences.getInt(_scheduledKey) == minutes) return;  // Aynı aralık zaten planlıysa tekrar kurma
      if (!_initialized) {  // İlk çağrıda
        await Workmanager().initialize(backgroundSyncDispatcher);  // WorkManager'ı giriş fonksiyonuyla başlat
        _initialized = true;  // Tekrar başlatılmasın
      }
      await Workmanager().cancelByUniqueName(_uniqueName);  // Eski planı iptal et
      if (minutes > 0) {  // Aralık 0 değilse yeni görev kur
        await Workmanager().registerPeriodicTask(  // Periyodik görevi kaydet
          _uniqueName,  // Benzersiz ad
          _taskName,  // Görev adı
          frequency: Duration(minutes: minutes < 15 ? 15 : minutes),  // Android en az 15 dk destekler; küçükse 15 yap
          constraints: Constraints(networkType: NetworkType.connected),  // Yalnızca internet varken çalış
        );
      }
      await preferences.setInt(_scheduledKey, minutes);  // Planlanan aralığı sakla
    } catch (error) {  // Beklenmeyen hata
      debugPrint('Arka plan eşitleme planlanamadı: $error');  // Planlama hatasını konsola yaz
    }
  }
}