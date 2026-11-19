import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_store.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/app_user.dart';
import '../../notifications/services/reminder_service.dart';
import 'admin_workspace_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    this.user,
    this.authService,
  });

  final AppStore store;
  final AppUser? user;
  final AuthService? authService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Map<String, bool> _notificationPreferences;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _notificationPreferences = {
      'inApp': widget.user?.notificationPreferences['inApp'] ?? true,
      'push': widget.user?.notificationPreferences['push'] ?? true,
    };
  }

  Future<void> _save({
    bool? phone,
    bool? windows,
    int? reminderMinutes,
    List<int>? reminderOffsets,
    List<int>? workingDays,
  }) => store.saveReminderSettings(
    phone: phone ?? store.phoneRemindersEnabled,
    windows: windows,
    reminderMinutes: reminderMinutes,
    reminderOffsets: reminderOffsets,
    workingDays: workingDays,
  );

  Future<void> _setReminderOffset(int offset, bool selected) async {
    final next = [...store.reminderOffsets];
    if (selected) {
      next.add(offset);
    } else {
      next.remove(offset);
    }
    if (next.isEmpty) {
      _showMessage('En az bir bildirim günü seçmelisiniz.');
      return;
    }
    await _save(reminderOffsets: next);
  }

  Future<void> _setWorkingDay(int weekday, bool selected) async {
    final next = [...store.workingDays];
    if (selected) {
      next.add(weekday);
    } else {
      next.remove(weekday);
    }
    if (next.isEmpty) {
      _showMessage('En az bir çalışma günü seçmelisiniz.');
      return;
    }
    await _save(workingDays: next);
  }

  Future<void> _setWindowsNotifications(bool enabled) async {
    if (!enabled) {
      await _save(windows: false);
      return;
    }
    try {
      final opened = await launchUrl(
        Uri.parse('ms-settings:notifications'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('Windows bildirim ayarları açılamadı.');
      }
      await ReminderService.instance.initialize();
      await ReminderService.instance.showWindowsTestNotification();
      await _save(windows: true);
      if (mounted) {
        _showMessage(
          'Windows bildirim ayarlarında RST Dolapdere bildirimlerini ve başlıkları etkinleştirin.',
        );
      }
    } catch (error) {
      _showMessage('Windows bildirimleri etkinleştirilemedi: $error');
    }
  }

  Future<void> _pickReminderTime() async {
    final initialTime = TimeOfDay(
      hour: store.reminderTimeMinutes ~/ 60,
      minute: store.reminderTimeMinutes % 60,
    );
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Bildirim saatini seçin',
    );
    if (selected == null) return;
    await _save(reminderMinutes: selected.hour * 60 + selected.minute);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setThemeMode(ThemeMode? mode) async {
    if (mode == null) return;
    try {
      await store.setThemeMode(mode);
    } catch (error) {
      if (mounted) _showMessage('Tema tercihi kaydedilemedi: $error');
    }
  }

  Future<void> _changePassword() async {
    final credentials = await showDialog<({String current, String next})>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
    if (credentials == null || !mounted) return;
    try {
      await widget.authService!.changePassword(
        currentPassword: credentials.current,
        newPassword: credentials.next,
      );
      if (mounted) _showMessage('Şifreniz değiştirildi.');
    } catch (_) {
      if (mounted) {
        _showMessage('Şifre değiştirilemedi. Mevcut şifrenizi kontrol edin.');
      }
    }
  }

  Future<void> _setPersonalNotification(String key, bool value) async {
    final authService = widget.authService;
    if (authService == null) return;
    final next = {..._notificationPreferences, key: value};
    try {
      if (key == 'push' && value) {
        final messaging = FirebaseMessaging.instance;
        final permission = await messaging.requestPermission();
        if (permission.authorizationStatus == AuthorizationStatus.denied) {
          throw StateError('Push bildirim izni verilmedi.');
        }
        // ignore: deprecated_member_use
        final token = await messaging.getToken(
          vapidKey:
              kIsWeb &&
                  const String.fromEnvironment('FIREBASE_VAPID_KEY').isNotEmpty
              ? const String.fromEnvironment('FIREBASE_VAPID_KEY')
              : null,
        );
        if (token != null && token.isNotEmpty) {
          await authService.registerPushToken(token);
        } else {
          throw StateError('Push tokenı alınamadı.');
        }
      }
      await authService.updateOwnNotificationPreferences(next);
      if (mounted) setState(() => _notificationPreferences[key] = value);
    } catch (error) {
      if (mounted) {
        _showMessage('Bildirim tercihi kaydedilemedi: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ayarlar',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Görünüm',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: store.themeMode.value,
                    decoration: const InputDecoration(
                      labelText: 'Tema',
                      prefixIcon: Icon(Icons.palette_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Açık'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Koyu'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('Sistem'),
                      ),
                    ],
                    onChanged: _setThemeMode,
                  ),
                ],
              ),
            ),
          ),
          if (widget.user != null && widget.authService != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(widget.user!.username),
                    subtitle: Text(widget.user!.role.name),
                    trailing: IconButton(
                      tooltip: 'Oturumu kapat',
                      onPressed: widget.authService!.signOut,
                      icon: const Icon(Icons.logout),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _changePassword,
                      icon: const Icon(Icons.password_outlined),
                      label: const Text('Şifre değiştir'),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Uygulama içi bildirimler'),
                    value: _notificationPreferences['inApp']!,
                    onChanged: (value) =>
                        _setPersonalNotification('inApp', value),
                  ),
                  SwitchListTile(
                    title: const Text('Push bildirimleri'),
                    value: _notificationPreferences['push']!,
                    onChanged: (value) =>
                        _setPersonalNotification('push', value),
                  ),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: widget.authService!.watchInbox(widget.user!.uid),
                    builder: (context, snapshot) {
                      final messages =
                          snapshot.data ?? const <Map<String, dynamic>>[];
                      final unread = messages
                          .where((item) => item['read'] != true)
                          .length;
                      return ExpansionTile(
                        leading: const Icon(Icons.inbox_outlined),
                        title: const Text('Gelen kutusu'),
                        subtitle: Text('$unread okunmamış bildirim'),
                        children: [
                          if (snapshot.hasError)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Bildirimler alınamadı: ${snapshot.error}',
                              ),
                            ),
                          if (messages.isEmpty && !snapshot.hasError)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Henüz bildirim yok.'),
                            ),
                          for (final item in messages)
                            ListTile(
                              leading: Icon(
                                item['read'] == true
                                    ? Icons.mark_email_read_outlined
                                    : Icons.mark_email_unread_outlined,
                              ),
                              title: Text(
                                item['title'] as String? ?? 'Bildirim',
                              ),
                              subtitle: Text(item['message'] as String? ?? ''),
                              onTap: item['read'] == true
                                  ? null
                                  : () => widget.authService!.markInboxRead(
                                      widget.user!.uid,
                                      item['id'] as String,
                                    ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
          if ((widget.user?.role == AppRole.admin ||
                  widget.user?.role == AppRole.manager) &&
              widget.authService != null) ...[
            const SizedBox(height: 16),
            AdminWorkspacePanel(
              authService: widget.authService!,
              currentRole: widget.user!.role,
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('Telefon bildirimi'),
                  subtitle: Text(
                    'Android ve iOS: ${_reminderOffsetLabel(store.reminderOffsets)}',
                  ),
                  value: store.phoneRemindersEnabled,
                  onChanged: (value) => _save(phone: value),
                ),
                if (defaultTargetPlatform == TargetPlatform.windows) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(
                      Icons.desktop_windows_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Windows masaüstü bildirimi'),
                    subtitle: const Text(
                      'Açınca Windows bildirim ayarları açılır; izin Windows tarafından yönetilir',
                    ),
                    value: store.windowsRemindersEnabled,
                    onChanged: _setWindowsNotifications,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Çalışma günleri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hatırlatma seçili olmayan güne denk gelirse sonraki çalışma gününe ertelenir.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final entry in AppStore.weekdayLabels.entries)
                        FilterChip(
                          label: Text(entry.value),
                          selected: store.workingDays.contains(entry.key),
                          onSelected: (selected) =>
                              _setWorkingDay(entry.key, selected),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bildirim günleri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sözleşme bitişinden kaç gün önce hatırlatma gönderilsin?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final offset in AppStore.availableReminderOffsets)
                        FilterChip(
                          label: Text(offset == 0 ? 'Son gün' : '$offset gün'),
                          selected: store.reminderOffsets.contains(offset),
                          onSelected: (selected) =>
                              _setReminderOffset(offset, selected),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.primary),
              title: const Text('Bildirim gönderme saati'),
              subtitle: Text(
                TimeOfDay(
                  hour: store.reminderTimeMinutes ~/ 60,
                  minute: store.reminderTimeMinutes % 60,
                ).format(context),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _pickReminderTime,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                store.cloudSyncEnabled
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: store.syncError == null
                    ? AppColors.primary
                    : AppColors.danger,
              ),
              title: const Text('Firestore veritabanı'),
              subtitle: Text(
                !store.cloudSyncEnabled
                    ? store.syncError ??
                          'Firestore bu platformda kapalı; kayıtlar cihazda tutuluyor.'
                    : store.syncError?.contains('permission-denied') == true
                    ? 'Erişim reddedildi. Firebase Console’da Firestore kurallarını yayımlayın: firebase deploy --only firestore:rules --project deresozlesmetakip'
                    : store.syncError != null
                    ? 'Bağlantı hatası: ${store.syncError}'
                    : store.isCloudSyncing
                    ? 'Firestore ile eşitleniyor...'
                    : 'Firestore bağlantısı etkin; veriler anlık eşitlenir.',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  String _reminderOffsetLabel(List<int> offsets) {
    final labels = offsets
        .map((offset) => offset == 0 ? 'son gün' : '$offset gün kala')
        .join(', ');
    return labels;
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((current: _current.text, next: _next.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Şifre değiştir'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mevcut şifre'),
              validator: (value) => value == null || value.isEmpty
                  ? 'Mevcut şifrenizi girin.'
                  : null,
            ),
            TextFormField(
              controller: _next,
              obscureText: true,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Yeni şifre',
                helperText: 'En az 10 karakter',
              ),
              validator: (value) => value == null || value.length < 10
                  ? 'En az 10 karakter girin.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Değiştir')),
    ],
  );
}
