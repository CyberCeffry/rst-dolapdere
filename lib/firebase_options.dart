import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError('Firebase bu platform için yapılandırılmadı.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDk3Rw3xlq_Zxs0rgmV5Xy0qylxiV46GW0',
    appId: '1:18751633043:web:d1f10d8f18271a8a0bff66',
    messagingSenderId: '18751633043',
    projectId: 'deresozlesmetakip',
    authDomain: 'deresozlesmetakip.firebaseapp.com',
    storageBucket: 'deresozlesmetakip.firebasestorage.app',
    measurementId: 'G-SQWJP7HF23',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDAQlP3A_I-Vo2cRNLKxOuP0KsTT7o6ep4',
    appId: '1:18751633043:android:bb25dba29ff2b3d60bff66',
    messagingSenderId: '18751633043',
    projectId: 'deresozlesmetakip',
    storageBucket: 'deresozlesmetakip.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCwsQHVpnRAx7DtQW5b8QUoxFsfLkmPBDQ',
    appId: '1:18751633043:ios:10c5a8057e715b810bff66',
    messagingSenderId: '18751633043',
    projectId: 'deresozlesmetakip',
    storageBucket: 'deresozlesmetakip.firebasestorage.app',
    iosBundleId: 'com.example.dereSozlesmeTakip',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCwsQHVpnRAx7DtQW5b8QUoxFsfLkmPBDQ',
    appId: '1:18751633043:ios:10c5a8057e715b810bff66',
    messagingSenderId: '18751633043',
    projectId: 'deresozlesmetakip',
    storageBucket: 'deresozlesmetakip.firebasestorage.app',
    iosBundleId: 'com.example.dereSozlesmeTakip',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDk3Rw3xlq_Zxs0rgmV5Xy0qylxiV46GW0',
    appId: '1:18751633043:web:4c68be02416fb3520bff66',
    messagingSenderId: '18751633043',
    projectId: 'deresozlesmetakip',
    authDomain: 'deresozlesmetakip.firebaseapp.com',
    storageBucket: 'deresozlesmetakip.firebasestorage.app',
    measurementId: 'G-CJ3WC255NE',
  );
}
