import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/services/app_store.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../features/notifications/services/reminder_service.dart';
import '../../models/app_user.dart';
import '../../shared/layouts/main_layout.dart';

class AuthenticatedApplication extends StatelessWidget {
  const AuthenticatedApplication({super.key, required this.firestore});

  final FirebaseFirestore firestore;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RST Dolapdere',
    debugShowCheckedModeBanner: false,
    locale: const Locale('tr', 'TR'),
    supportedLocales: const [Locale('tr', 'TR')],
    theme: AppTheme.lightTheme,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: _AuthGate(firestore: firestore),
  );
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.firestore});

  final FirebaseFirestore firestore;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  static const _webVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  final _authService = AuthService();
  final _mainLayoutKey = GlobalKey<MainLayoutState>();
  late Future<AppUser?> _profile;
  Future<AppStore>? _storeFuture;
  String? _storeUid;
  StreamSubscription<AppUser?>? _profileSubscription;
  String? _invalidUser;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile(_authService.currentUser);
  }

  Future<AppUser?> _loadProfile(User? user) async {
    if (user == null) return null;
    try {
      final profile = await _authService.loadProfile(user.uid);
      if (profile == null || !profile.isActive) {
        await _authService.signOut();
        if (mounted) setState(() => _invalidUser = 'Hesabınız etkin değil.');
        return null;
      }
      return profile;
    } catch (error) {
      if (mounted) {
        setState(() => _invalidUser = 'Kullanıcı profili alınamadı: $error');
      }
      return null;
    }
  }

  void _onSignedIn(AppUser profile) {
    _profileSubscription?.cancel();
    setState(() {
      _invalidUser = null;
      _profile = Future.value(profile);
      _storeUid = null;
      _storeFuture = null;
    });
  }

  Future<AppStore> _loadStore(AppUser profile) {
    if (_storeFuture == null || _storeUid != profile.uid) {
      _storeUid = profile.uid;
      _storeFuture = _initializeUserStore(profile);
    }
    return _storeFuture!;
  }

  Future<AppStore> _initializeUserStore(AppUser profile) async {
    if (profile.notificationPreferences['push'] != false) {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission();
        // ignore: deprecated_member_use
        final token = await messaging.getToken(
          vapidKey: kIsWeb && _webVapidKey.isNotEmpty ? _webVapidKey : null,
        );
        if (token != null && token.isNotEmpty) {
          await _authService.registerPushToken(token);
        }
        // ignore: deprecated_member_use
        messaging.onTokenRefresh.listen((token) {
          _authService.registerPushToken(token);
        });
      } catch (_) {
        // Authentication and contract access remain available if push setup is incomplete.
      }
    }
    final store = await AppStore.initialize(
      firestore: widget.firestore,
      user: profile,
    );
    await _profileSubscription?.cancel();
    _profileSubscription = _authService.watchProfile(profile.uid).listen((
      latest,
    ) {
      if (latest == null || !latest.isActive) {
        _authService.signOut();
        if (mounted) {
          setState(() => _invalidUser = 'Hesabınız devre dışı bırakıldı.');
        }
        return;
      }
      final accessChanged =
          latest.role != profile.role ||
          latest.permissions.toString() != profile.permissions.toString() ||
          latest.assignedContractIds.join(',') !=
              profile.assignedContractIds.join(',') ||
          latest.assignedCustomerIds.join(',') !=
              profile.assignedCustomerIds.join(',') ||
          latest.assignedAdSpaceIds.join(',') !=
              profile.assignedAdSpaceIds.join(',');
      if (accessChanged && mounted) {
        setState(() {
          _profile = Future.value(latest);
          _storeUid = null;
          _storeFuture = null;
        });
      }
    }, onError: (_) => _authService.signOut());
    ReminderService.instance.setReviewHandler((contractId) {
      _mainLayoutKey.currentState?.openContract(contractId);
    });
    try {
      await ReminderService.instance.initialize(
        windowsEnabled: store.windowsRemindersEnabled,
      );
      await ReminderService.instance.sync(store);
    } catch (_) {
      // Sign-in remains available if device reminders are not configured.
    }
    store.addListener(() => ReminderService.instance.sync(store));
    return store;
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _authService.authChanges,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          _authService.currentUser == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data ?? _authService.currentUser;
      if (user == null) {
        return LoginScreen(
          authService: _authService,
          errorMessage: _invalidUser,
          onSignedIn: _onSignedIn,
        );
      }
      return FutureBuilder<AppUser?>(
        future: _profile,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final profile = profileSnapshot.data;
          if (profile == null) {
            return LoginScreen(
              authService: _authService,
              errorMessage: _invalidUser ?? 'Hesap bilgileri bulunamadı.',
              onSignedIn: _onSignedIn,
            );
          }
          return FutureBuilder<AppStore>(
            future: _loadStore(profile),
            builder: (context, storeSnapshot) {
              if (storeSnapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (storeSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Text('Veriler yüklenemedi: ${storeSnapshot.error}'),
                  ),
                );
              }
              final store = storeSnapshot.requireData;
              return MainLayout(
                key: _mainLayoutKey,
                store: store,
                user: profile,
                authService: _authService,
              );
            },
          );
        },
      );
    },
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.onSignedIn,
    this.errorMessage,
  });

  final AuthService authService;
  final ValueChanged<AppUser> onSignedIn;
  final String? errorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await widget.authService.signIn(
        username: _username.text,
        password: _password.text,
      );
      if (mounted) widget.onSignedIn(profile);
    } catch (_) {
      if (mounted) setState(() => _error = 'Kullanıcı adı veya şifre hatalı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 420,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.business_outlined,
                      size: 42,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'RST Dolapdere',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı adı',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Kullanıcı adınızı girin.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      onFieldSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Şifreyi göster'
                              : 'Şifreyi gizle',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Şifrenizi girin.'
                          : null,
                    ),
                    if (_error != null || widget.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error ?? widget.errorMessage!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Text('Giriş yap'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
