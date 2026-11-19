import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../notifications/services/reminder_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppStore get store => widget.store;

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
          _SyncCard(store: store),
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

class _SyncCard extends StatefulWidget {
  const _SyncCard({required this.store});

  final AppStore store;

  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  AppStore get store => widget.store;

  Future<void> _syncNow() async {
    await store.syncNow();
    if (!mounted) return;
    final error = store.syncError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Eşitleme tamamlandı.'
              : 'Eşitleme başarısız: ${_errorText(error)}',
        ),
      ),
    );
  }

  Future<void> _setInterval(int? minutes) async {
    if (minutes == null) return;
    await store.setSyncIntervalMinutes(minutes);
    if (mounted) setState(() {});
  }

  String _errorText(String error) => error.contains('permission-denied')
      ? 'Erişim reddedildi. Firebase Console’da Firestore kurallarını yayımlayın: firebase deploy --only firestore:rules --project deresozlesmetakip'
      : error;

  String _lastSyncText(DateTime? value) {
    if (value == null) return 'henüz yapılmadı';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: store.syncStatus,
      builder: (context, status, _) {
        final enabled = store.cloudSyncEnabled;
        final failed = status.error != null;
        final subtitle = !enabled
            ? (status.error ??
                  'Firebase bu platformda kapalı; kayıtlar cihazda tutuluyor.')
            : failed
            ? 'Bağlantı hatası: ${_errorText(status.error!)}'
            : status.busy
            ? 'Eşitleniyor...'
            : 'Son eşitleme: ${_lastSyncText(status.lastSync)}';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Firebase',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    enabled && !failed
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: failed ? AppColors.danger : AppColors.primary,
                  ),
                  title: const Text('Veritabanı eşitleme'),
                  subtitle: Text(subtitle),
                ),
                if (status.pending > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${status.pending} değişiklik Firebase’e gönderilmeyi bekliyor.',
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Değişiklikleri anında gönder'),
                  subtitle: const Text(
                    'Kapalıyken kayıtlar cihazda bekler; seçilen aralıkta veya "Şimdi eşitle" ile gönderilir.',
                  ),
                  value: store.instantSyncEnabled,
                  onChanged: enabled
                      ? (value) async {
                          await store.setInstantSyncEnabled(value);
                          if (mounted) setState(() {});
                        }
                      : null,
                ),
                DropdownButtonFormField<int>(
                  initialValue: store.syncIntervalMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Otomatik eşitleme aralığı',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  items: [
                    for (final minutes in AppStore.availableSyncIntervals)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(
                          minutes == 0
                              ? 'Kapalı (yalnızca elle)'
                              : '$minutes dakikada bir',
                        ),
                      ),
                  ],
                  onChanged: enabled ? _setInterval : null,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: enabled && !status.busy ? _syncNow : null,
                  icon: status.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Şimdi eşitle'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Eşitlemede yalnızca değişen kayıtlar gönderilir ve son eşitlemeden beri değişenler alınır.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
