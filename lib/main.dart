import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/services/app_store.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';
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
      defaultTargetPlatform == TargetPlatform.macOS;
  if (firebaseSupported) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firestore = FirebaseFirestore.instance;
    } catch (error) {
      cloudError = 'Firebase başlatılamadı: $error';
    }
  } else {
    cloudError = 'Bu platformda kayıtlar cihazda tutuluyor.';
  }
  if (firestore != null) {
    runApp(AuthenticatedApplication(firestore: firestore));
    return;
  }
  runApp(_AuthenticationUnavailableApp(message: cloudError));
}

class _AuthenticationUnavailableApp extends StatelessWidget {
  const _AuthenticationUnavailableApp({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RST Dolapdere',
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 44),
                const SizedBox(height: 16),
                const Text(
                  'Güvenli oturum açılamadı',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message ??
                      'Bu platform için Firebase Authentication ve Firestore yapılandırması gerekiyor.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class RSTDolapdereApp extends StatelessWidget {
  const RSTDolapdereApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RST Dolapdere',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.lightTheme,
      home: MainLayout(key: mainLayoutKey, store: store),
    );
  }
}
