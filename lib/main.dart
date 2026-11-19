import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/services/app_store.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'shared/layouts/main_layout.dart';

final mainLayoutKey = GlobalKey<MainLayoutState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseFirestore? firestore;
  String? cloudError;
  final firebaseSupported =
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;
  if (firebaseSupported) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firestore = FirebaseFirestore.instance;
      // Veriler zaten cihazda (SharedPreferences) tutuluyor; Firestore'un ikinci
      // bir yerel önbelleği gereksiz iş yükü yaratıyordu.
      firestore.settings = const Settings(persistenceEnabled: false);
    } catch (error) {
      cloudError = 'Firebase başlatılamadı: $error';
    }
  } else {
    cloudError = 'Bu platformda kayıtlar cihazda tutuluyor.';
  }
  final store = await AppStore.initialize(
    firestore: firestore,
    initialSyncError: cloudError,
  );
  runApp(RSTDolapdereApp(store: store));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    mainLayoutKey.currentState?.initializeReminders();
  });
}

class RSTDolapdereApp extends StatelessWidget {
  const RSTDolapdereApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: store.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'RST Dolapdere',
        debugShowCheckedModeBanner: false,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: MainLayout(key: mainLayoutKey, store: store),
      ),
    );
  }
}
