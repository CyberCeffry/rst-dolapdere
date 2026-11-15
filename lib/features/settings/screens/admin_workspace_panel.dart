import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/app_user.dart';

class AdminWorkspacePanel extends StatelessWidget {
  const AdminWorkspacePanel({
    super.key,
    required this.authService,
    required this.currentRole,
  });

  final AuthService authService;
  final AppRole currentRole;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Card(
        child: StreamBuilder<List<AppUser>>(
          stream: authService.watchUsers(),
          builder: (context, snapshot) {
            final users = snapshot.data ?? const <AppUser>[];
            return ExpansionTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Kullanıcılar ve roller'),
              subtitle: Text('${users.length} kullanıcı'),
              trailing: IconButton(
                tooltip: 'Kullanıcı ekle',
                onPressed: () =>
                    _editUser(context, authService, currentRole: currentRole),
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
              children: [
                if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Kullanıcılar yüklenemedi: ${snapshot.error}'),
                  ),
                for (final user in users)
                  ListTile(
                    leading: Icon(
                      user.isActive
                          ? Icons.person_outline
                          : Icons.person_off_outlined,
                      color: user.isActive
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(user.username),
                    subtitle: Text(
                      '${_roleLabel(user.role)} • ${user.isActive ? 'Etkin' : 'Pasif'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Kullanıcı işlemleri',
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await _editUser(
                            context,
                            authService,
                            user: user,
                            currentRole: currentRole,
                          );
                        } else if (action == 'active') {
                          await authService.updateUser(
                            uid: user.uid,
                            role: user.role,
                            isActive: !user.isActive,
                            permissions: user.permissions,
                            email: user.email,
                          );
                        } else if (action == 'notify') {
                          await _sendNotification(context, authService, user);
                        } else if (action == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Kullanıcı hesabını kapat'),
                              content: Text(
                                '${user.username} hesabı devre dışı bırakılsın mı? Hesap verileri korunur.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Vazgeç'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Kapat'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await authService.deleteUser(user.uid);
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        if (currentRole == AppRole.admin ||
                            user.role != AppRole.admin) ...[
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Rol ve izinleri düzenle'),
                          ),
                          PopupMenuItem(
                            value: 'active',
                            child: Text(
                              user.isActive ? 'Pasife al' : 'Etkinleştir',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Hesabı kapat'),
                          ),
                        ],
                        const PopupMenuItem(
                          value: 'notify',
                          child: Text('Bildirim gönder'),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      Card(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: authService.watchContractRequests(),
          builder: (context, snapshot) {
            final requests = snapshot.data ?? const <Map<String, dynamic>>[];
            return ExpansionTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Sözleşme onayları'),
              subtitle: Text('${requests.length} bekleyen talep'),
              children: [
                if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Onay talepleri yüklenemedi: ${snapshot.error}',
                    ),
                  ),
                if (requests.isEmpty && !snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Bekleyen onay yok.'),
                  ),
                for (final request in requests)
                  _approvalTile(context, authService, request),
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _approvalTile(
    BuildContext context,
    AuthService authService,
    Map<String, dynamic> request,
  ) {
    final contract = Map<String, dynamic>.from(
      request['contract'] as Map? ?? {},
    );
    final create = request['operation'] == 'create';
    final price = contract['monthlyPrice'] ?? 0;
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(create ? 'Yeni sözleşme' : 'Sözleşme uzatma'),
      subtitle: Text(
        'Birim fiyat: $price ₺ • Talep: ${request['submittedBy'] ?? '-'}',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Reddet',
            onPressed: () => authService.reviewContractRequest(
              requestId: request['id'] as String,
              approve: false,
            ),
            icon: const Icon(Icons.close, color: AppColors.danger),
          ),
          IconButton(
            tooltip: 'Onayla',
            onPressed: () => authService.reviewContractRequest(
              requestId: request['id'] as String,
              approve: true,
            ),
            icon: const Icon(Icons.check, color: AppColors.success),
          ),
        ],
      ),
    );
  }

  Future<void> _editUser(
    BuildContext context,
    AuthService authService, {
    AppUser? user,
    required AppRole currentRole,
  }) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (context) => _UserFormDialog(
        user: user,
        allowAdminRole: currentRole == AppRole.admin,
      ),
    );
    if (result == null) return;
    try {
      if (user == null) {
        await authService.createUser(
          username: result.username,
          initialPassword: result.password,
          role: result.role,
          isActive: result.isActive,
          permissions: result.permissions,
          email: result.email,
        );
      } else {
        await authService.updateUser(
          uid: user.uid,
          role: result.role,
          isActive: result.isActive,
          permissions: result.permissions,
          email: result.email,
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (!context.mounted) return;
      final message = switch (error.code) {
        'not-found' =>
          'Kullanıcı yönetimi sunucusu yayınlanmamış. Firebase Functions dağıtımı gerekiyor.',
        'permission-denied' =>
          'Bu kullanıcıyı ekleme veya düzenleme yetkiniz yok.',
        'already-exists' => 'Bu kullanıcı adı zaten kullanımda.',
        'invalid-argument' =>
          error.message ?? 'Kullanıcı bilgilerini kontrol edin.',
        'unavailable' => 'Firebase Functions servisine ulaşılamıyor.',
        'internal' =>
          'Sunucu kullanıcı oluşturmayı tamamlayamadı. Firebase Functions deploy durumunu ve adminCreateUser günlüklerini kontrol edin. ${error.message ?? ''}',
        _ => error.message ?? 'İşlem tamamlanamadı (${error.code}).',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      final message = switch (error.code) {
        'email-already-in-use' =>
          'Bu kullanıcı adıyla Auth hesabı zaten var. Önceki başarısız denemeden kalan hesap varsa Firebase Console > Authentication bölümünden temizleyin.',
        'weak-password' =>
          'Başlangıç şifresi Firebase politikasını karşılamıyor.',
        'invalid-email' =>
          'Kullanıcı adı e-posta aliası oluşturmak için geçersiz.',
        'network-request-failed' =>
          'Firebase Authentication servisine ulaşılamıyor.',
        _ => error.message ?? 'Authentication hatası: ${error.code}',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
      );
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      final message = error.code == 'permission-denied'
          ? 'Firestore kullanıcı oluşturma izni vermedi. Güncel firestore.rules dosyasını deploy edin.'
          : error.code == 'already-exists'
          ? 'Bu kullanıcı adı zaten kullanımda.'
          : error.message ?? 'Firestore hatası: ${error.code}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kullanıcı kaydedilemedi: $error')),
      );
    }
  }

  Future<void> _sendNotification(
    BuildContext context,
    AuthService authService,
    AppUser user,
  ) async {
    final title = TextEditingController();
    final message = TextEditingController();
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${user.username} kullanıcısına bildirim'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Başlık'),
              ),
              TextField(
                controller: message,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Mesaj'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (shouldSend == true) {
      await authService.sendUserNotification(
        userId: user.uid,
        title: title.text,
        message: message.text,
      );
    }
    title.dispose();
    message.dispose();
  }

  String _roleLabel(AppRole role) => switch (role) {
    AppRole.admin => 'Sistem yöneticisi',
    AppRole.manager => 'Yönetici',
    AppRole.supervisor => 'Sorumlu',
  };
}

class _UserFormResult {
  const _UserFormResult({
    required this.username,
    required this.password,
    required this.role,
    required this.isActive,
    required this.permissions,
    required this.email,
  });

  final String username;
  final String password;
  final AppRole role;
  final bool isActive;
  final Map<String, bool> permissions;
  final String email;
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user, required this.allowAdminRole});
  final AppUser? user;
  final bool allowAdminRole;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _email;
  late AppRole _role;
  late bool _isActive;
  late final Map<String, bool> _permissions;

  String? _validateUsername(String? value) {
    final username = value?.trim().toLowerCase() ?? '';
    if (username.length < 3 || username.length > 32) {
      return 'Kullanıcı adı 3-32 karakter olmalı.';
    }
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(username)) {
      return 'Yalnızca İngilizce harf, sayı, nokta, tire ve alt çizgi kullanın.';
    }
    return null;
  }

  static const _modules = {
    'dashboard': 'Ana panel',
    'adSpaces': 'Reklam alanları',
    'customers': 'Kiracılar',
    'contracts': 'Sözleşmeler',
    'notifications': 'Bildirimler',
    'settings': 'Ayarlar',
  };

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _username = TextEditingController(text: user?.username ?? '');
    _password = TextEditingController();
    _email = TextEditingController(text: user?.email ?? '');
    _role = user?.role ?? AppRole.supervisor;
    _isActive = user?.isActive ?? true;
    _permissions = {
      for (final key in _modules.keys) key: user?.permissions[key] ?? false,
    };
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.user == null ? 'Kullanıcı ekle' : 'Kullanıcı rolü ve izinleri',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.user == null)
                TextFormField(
                  controller: _username,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı adı',
                    hintText: 'ornek.kullanici',
                  ),
                  validator: _validateUsername,
                ),
              if (widget.user == null)
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Başlangıç şifresi',
                    helperText: 'En az 10 karakter',
                  ),
                  validator: (value) => (value?.length ?? 0) < 10
                      ? 'Şifre en az 10 karakter olmalı.'
                      : null,
                ),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-posta (bildirim için)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AppRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [
                  const DropdownMenuItem(
                    value: AppRole.manager,
                    child: Text('Yönetici'),
                  ),
                  const DropdownMenuItem(
                    value: AppRole.supervisor,
                    child: Text('Sorumlu'),
                  ),
                  if (widget.allowAdminRole)
                    const DropdownMenuItem(
                      value: AppRole.admin,
                      child: Text('Sistem yöneticisi'),
                    ),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kullanıcı etkin'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (_role == AppRole.supervisor) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Erişim izinleri'),
                ),
                for (final entry in _modules.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    value: _permissions[entry.key],
                    onChanged: (value) => setState(
                      () => _permissions[entry.key] = value ?? false,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _UserFormResult(
              username: _username.text.trim().toLowerCase(),
              password: _password.text,
              role: _role,
              isActive: _isActive,
              permissions: _permissions,
              email: _email.text.trim(),
            ),
          );
        },
        child: const Text('Kaydet'),
      ),
    ],
  );
}
