import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../firebase_options.dart';
import 'app_store.dart';

const String _uniqueName = 'rst_periodic_sync';
const String _taskName = 'rst_periodic_sync_task';
const String _scheduledKey = 'bgSyncScheduledMinutes';

/// Android arka plan görevi (WorkManager) giriş noktası.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final firestore = FirebaseFirestore.instance;
      try {
        firestore.settings = const Settings(persistenceEnabled: false);
      } catch (_) {}
      return await AppStore.runBackgroundSync(firestore);
    } catch (error) {
      debugPrint('Arka plan eşitleme hatası: $error');
      return false;
    }
  });
}

/// Uygulama kapalıyken / arka plandayken de seçilen süreye göre eşitleme.
/// Yalnızca Android'de çalışır (WorkManager en az 15 dakika destekler).
/// Windows'ta uygulama açık olduğu sürece mevcut zamanlayıcı çalışır.
class BackgroundSync {
  static bool get supported => !kIsWeb && Platform.isAndroid;
  static bool _initialized = false;

  static Future<void> schedule(int minutes, {bool force = false}) async {
    if (!supported) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!force && preferences.getInt(_scheduledKey) == minutes) return;
      if (!_initialized) {
        await Workmanager().initialize(backgroundSyncDispatcher);
        _initialized = true;
      }
      await Workmanager().cancelByUniqueName(_uniqueName);
      if (minutes > 0) {
        await Workmanager().registerPeriodicTask(
          _uniqueName,
          _taskName,
          frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }
      await preferences.setInt(_scheduledKey, minutes);
    } catch (error) {
      debugPrint('Arka plan eşitleme planlanamadı: $error');
    }
  }
}