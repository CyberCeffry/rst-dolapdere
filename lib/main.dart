import 'dart:async';  // unawaited() gibi asenkron yardımcılar için

import 'package:cloud_firestore/cloud_firestore.dart';  // Firestore (bulut veritabanı) sınıfları
import 'package:firebase_core/firebase_core.dart';  // Firebase'i başlatan çekirdek paket
import 'package:flutter/foundation.dart';  // kIsWeb ve defaultTargetPlatform için
import 'package:flutter/material.dart';  // Material arayüz bileşenleri (MaterialApp, Widget vb.)
import 'package:flutter_localizations/flutter_localizations.dart';  // Türkçe tarih/metin yerelleştirmesi

import 'core/services/app_store.dart';  // Uygulamanın tüm verisini tutan merkezi sınıf
import 'core/services/background_sync.dart';  // Android arka plan eşitleme planlayıcısı
import 'core/theme/app_theme.dart';  // Açık/koyu tema tanımları
import 'firebase_options.dart';  // Firebase proje ayarları (platform bazlı)
import 'shared/layouts/main_layout.dart';  // Ana iskelet: menü + sayfa alanı

final mainLayoutKey = GlobalKey<MainLayoutState>();  // Ana iskelete dışarıdan erişmek için anahtar (bildirimleri başlatmakta kullanılır)

Future<void> main() async {  // Uygulamanın giriş noktası; asenkron çünkü Firebase beklenecek
  WidgetsFlutterBinding.ensureInitialized();  // runApp'ten önce Flutter motorunu hazırlar (eklentiler için şart)
  FirebaseFirestore? firestore;  // Firestore nesnesi; desteklenmeyen platformda null kalır
  String? cloudError;  // Bulut başlatma hatası metni (varsa ayarlarda gösterilir)
  final firebaseSupported =  // Bu platformda Firebase kullanılabilir mi?
      kIsWeb ||  // Web ise destekli
      defaultTargetPlatform == TargetPlatform.android ||  // Android ise destekli
      defaultTargetPlatform == TargetPlatform.iOS ||  // iOS ise destekli
      defaultTargetPlatform == TargetPlatform.macOS ||  // macOS ise destekli
      defaultTargetPlatform == TargetPlatform.windows;  // Windows ise destekli (Linux hariç)
  if (firebaseSupported) {  // Platform destekliyorsa Firebase'i kurmayı dene
    try {  // Hata olursa uygulama çökmesin diye korumalı blok
      await Firebase.initializeApp(  // Firebase'i başlat ve bitmesini bekle
        options: DefaultFirebaseOptions.currentPlatform,  // Çalışılan platforma uygun proje anahtarlarını ver
      );
      firestore = FirebaseFirestore.instance;  // Hazır Firestore örneğini al
      // Veriler zaten cihazda (SharedPreferences) tutuluyor; Firestore'un ikinci
      // bir yerel önbelleği gereksiz iş yükü yaratıyordu.
      firestore.settings = const Settings(persistenceEnabled: false);  // Firestore'un kendi yerel önbelleğini kapat
    } catch (error) {  // Başlatma başarısızsa buraya düşer
      cloudError = 'Firebase başlatılamadı: $error';  // Hatayı metin olarak sakla
    }
  } else {  // Platform desteklenmiyorsa
    cloudError = 'Bu platformda kayıtlar cihazda tutuluyor.';  // Kullanıcıya bilgi mesajı: veri yalnız cihazda
  }
  final store = await AppStore.initialize(  // Merkezi veri deposunu oluştur ve kayıtları cihazdan yükle
    firestore: firestore,  // Bulut bağlantısını depoya ver (null olabilir)
    initialSyncError: cloudError,  // Başlangıç hatasını depoya ilet
  );
  if (firestore != null) {  // Yalnızca bulut varsa arka plan eşitlemesi planla
    unawaited(BackgroundSync.schedule(store.syncIntervalMinutes));  // Seçili dakika aralığında periyodik görevi kur (beklemeden)
  }
  runApp(RSTDolapdereApp(store: store));  // Arayüzü ekrana basar; uygulama burada başlar
  WidgetsBinding.instance.addPostFrameCallback((_) {  // İlk çizim bittikten sonra çalışacak işi kaydet
    mainLayoutKey.currentState?.initializeReminders();  // Ana iskele hazır olunca hatırlatma bildirimlerini kur
  });
}

class RSTDolapdereApp extends StatelessWidget {  // Kök widget; kendi içinde değişen durumu yok
  const RSTDolapdereApp({super.key, required this.store});  // Yapıcı: veri deposu zorunlu parametre

  final AppStore store;  // Tüm ekranlara dağıtılacak veri deposu

  @override  // Üst sınıftaki metodu ezdiğimizi belirtir
  Widget build(BuildContext context) {  // Bu widget'ın arayüzünü tarif eden metot
    return ValueListenableBuilder<ThemeMode>(  // Tema modu değişince MaterialApp'i yeniden kurar
      valueListenable: store.themeMode,  // Dinlenen değer: açık / koyu / sistem
      builder: (context, themeMode, _) => MaterialApp(  // Her tema değişiminde yeni MaterialApp üretir
        title: 'RST Dolapdere',  // İşletim sistemindeki uygulama başlığı
        debugShowCheckedModeBanner: false,  // Sağ üstteki DEBUG şeridini gizler
        locale: const Locale('tr', 'TR'),  // Uygulama dili Türkçe
        supportedLocales: const [Locale('tr', 'TR')],  // Yalnızca Türkçe desteklenir
        localizationsDelegates: GlobalMaterialLocalizations.delegates,  // Takvim, saat seçici vb. Material metinlerini Türkçeleştirir
        theme: AppTheme.lightTheme,  // Açık tema
        darkTheme: AppTheme.darkTheme,  // Koyu tema
        themeMode: themeMode,  // Kullanıcının seçtiği mod
        home: MainLayout(key: mainLayoutKey, store: store),  // İlk açılan sayfa: ana iskelet
      ),
    );
  }
}