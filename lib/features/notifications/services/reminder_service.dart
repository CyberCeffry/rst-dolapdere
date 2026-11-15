import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  ValueChanged<NotificationResponse>? _onNotificationResponse;

  void setNotificationHandler(ValueChanged<NotificationResponse> handler) {
    _onNotificationResponse = handler;
  }

  void setReviewHandler(ValueChanged<String> handler) {
    _onNotificationResponse = (response) {
      final action = response.actionId ?? '';
      final contractId = action.startsWith('contract:')
          ? action.substring('contract:'.length)
          : response.payload;
      if (contractId != null &&
          contractId.isNotEmpty &&
          !contractId.startsWith('expiring:')) {
        handler(contractId);
      }
    };
  }

  Future<void> initialize({bool windowsEnabled = false}) async {
    if (kIsWeb) {
      return;
    }
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.windows && !windowsEnabled) {
      return;
    }
    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS &&
        platform != TargetPlatform.windows) {
      return;
    }
    if (_ready) return;

    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Europe/Istanbul'));
    final notificationSettings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: const DarwinInitializationSettings(),
      windows: platform == TargetPlatform.windows
          ? const WindowsInitializationSettings(
              appName: 'RST Dolapdere',
              appUserModelId: 'RST.Dolapdere.Contracts',
              guid: '36a5b84a-4f37-4b13-9106-4271b786f289',
            )
          : null,
    );
    await _plugin.initialize(
      settings: notificationSettings,
      onDidReceiveNotificationResponse: (response) =>
          _onNotificationResponse?.call(response),
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _onNotificationResponse?.call(launchResponse);
    }
    if (platform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    _ready = true;
  }

  Future<void> sync(AppStore store) async {
    if (!_ready) {
      return;
    }
    await _plugin.cancelAll();
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows && !store.windowsRemindersEnabled) return;
    if (!isWindows && !store.phoneRemindersEnabled) return;

    for (final contract in store.activeContracts) {
      final space = store.adSpaceFor(contract.adSpaceId);
      final customer = store.customerFor(contract.customerId);
      if (space == null) continue;
      final offsets = [10, 5, 0];
      for (var index = 0; index < offsets.length; index++) {
        final days = offsets[index];
        final reminderDate = timezone.TZDateTime(
          timezone.local,
          contract.endDate.year,
          contract.endDate.month,
          contract.endDate.day - days,
          store.reminderTimeMinutes ~/ 60,
          store.reminderTimeMinutes % 60,
        );
        if (!reminderDate.isAfter(timezone.TZDateTime.now(timezone.local))) {
          continue;
        }
        final dayText = days == 0
            ? 'bugün sona eriyor'
            : '$days gün sonra sona eriyor';
        final customerName = customer?.name ?? 'Kiracı';
        await _plugin.zonedSchedule(
          id: _notificationId(contract.id, index),
          title: 'Sözleşme bitişi yaklaşıyor',
          body: '${space.name} alanındaki $customerName sözleşmesi $dayText.',
          scheduledDate: reminderDate,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'contract_reminders',
              'Sözleşme hatırlatmaları',
              channelDescription: 'Sözleşme bitiş tarihleri için hatırlatmalar',
              importance: Importance.high,
              priority: Priority.high,
              color: AppColors.primary,
            ),
            iOS: DarwinNotificationDetails(),
            windows: WindowsNotificationDetails(
              actions: [
                WindowsAction(
                  content: 'Süresi yaklaşanları aç',
                  arguments: 'expiring:${contract.id}',
                ),
                WindowsAction(
                  content: 'Bu sözleşmeyi aç',
                  arguments: 'contract:${contract.id}',
                ),
              ],
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: contract.id,
        );
      }
    }
  }

  int _notificationId(String id, int offsetIndex) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x07ffffff;
    }
    return hash * 10 + offsetIndex + 1;
  }
}
