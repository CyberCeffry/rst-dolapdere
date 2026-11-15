import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/business_day_helper.dart';
import '../../../core/utils/executable_path_stub.dart'
    if (dart.library.io) '../../../core/utils/executable_path_io.dart'
    as app_platform;

const _windowsAppName = 'RST Dolapdere';
const _windowsAppUserModelId = 'RST.Dolapdere.Contracts';
const _windowsActivatorGuid = '36a5b84a-4f37-4b13-9106-4271b786f289';
const _darwinReminderCategory = 'contract_reminders';

InitializationSettings _initializationSettings(TargetPlatform platform) {
  return InitializationSettings(
    android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          _darwinReminderCategory,
          actions: [
            DarwinNotificationAction.plain(
              'snooze',
              'Ertele...',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              'contract',
              'Sözleşmeyi aç',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              'expiring',
              'Yaklaşanları aç',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    ),
    windows: platform == TargetPlatform.windows
        ? WindowsInitializationSettings(
            appName: _windowsAppName,
            appUserModelId: _windowsAppUserModelId,
            guid: _windowsActivatorGuid,
            iconPath: app_platform.executablePath,
          )
        : null,
  );
}

NotificationDetails _notificationDetails(
  TargetPlatform platform, {
  String? contractId,
}) {
  final contractAction = contractId == null
      ? 'contract'
      : 'contract:$contractId';
  final expiringAction = contractId == null
      ? 'expiring'
      : 'expiring:$contractId';
  final snoozeAction = contractId == null ? 'snooze' : 'snooze:$contractId';
  return NotificationDetails(
    android: const AndroidNotificationDetails(
      'contract_reminders',
      'Sözleşme hatırlatmaları',
      channelDescription: 'Sözleşme bitiş tarihleri için hatırlatmalar',
      importance: Importance.high,
      priority: Priority.high,
      color: AppColors.primary,
      autoCancel: false,
      actions: [
        AndroidNotificationAction(
          'snooze',
          'Ertele...',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          'contract',
          'Sözleşmeyi aç',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          'expiring',
          'Yaklaşanları aç',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    ),
    iOS: const DarwinNotificationDetails(
      categoryIdentifier: _darwinReminderCategory,
      presentAlert: true,
      presentSound: true,
    ),
    windows: WindowsNotificationDetails(
      duration: WindowsNotificationDuration.long,
      actions: [
        WindowsAction(
          content: 'Ertele...',
          arguments: snoozeAction,
          activationType: WindowsActivationType.foreground,
          activationBehavior: WindowsNotificationBehavior.dismiss,
        ),
        WindowsAction(
          content: 'Sözleşmeyi aç',
          arguments: contractAction,
          activationType: WindowsActivationType.foreground,
          activationBehavior: WindowsNotificationBehavior.dismiss,
        ),
        WindowsAction(
          content: 'Yaklaşanları aç',
          arguments: expiringAction,
          activationType: WindowsActivationType.foreground,
          activationBehavior: WindowsNotificationBehavior.dismiss,
        ),
      ],
    ),
  );
}

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

  Future<void> initialize() async {
    if (kIsWeb) return;
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android &&
        platform != TargetPlatform.iOS &&
        platform != TargetPlatform.windows) {
      return;
    }
    if (_ready) return;

    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Europe/Istanbul'));
    await _plugin.initialize(
      settings: _initializationSettings(platform),
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
    if (platform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    _ready = true;
  }

  Future<void> snooze(
    String contractId,
    Duration duration,
    List<int> workingDays,
    DateTime endDate,
  ) async {
    if (!_ready) {
      throw StateError('Hatırlatma servisi henüz başlatılmadı.');
    }
    final requestedDate = timezone.TZDateTime.now(timezone.local).add(duration);
    final workingDate = BusinessDayHelper.nextWorkingDay(
      requestedDate,
      workingDays,
    );
    final daysRemaining = BusinessDayHelper.daysRemaining(endDate, workingDate);
    final remainingText = switch (daysRemaining) {
      0 => 'Sözleşme bugün sona eriyor.',
      > 0 => 'Sözleşmenin bitmesine $daysRemaining gün kalıyor.',
      _ => 'Sözleşme ${daysRemaining.abs()} gün önce sona erdi.',
    };
    await _plugin.zonedSchedule(
      id: _snoozedNotificationId(contractId),
      title: 'Ertelenen sözleşme hatırlatması',
      body: remainingText,
      scheduledDate: timezone.TZDateTime(
        timezone.local,
        workingDate.year,
        workingDate.month,
        workingDate.day,
        requestedDate.hour,
        requestedDate.minute,
      ),
      notificationDetails: _notificationDetails(
        defaultTargetPlatform,
        contractId: contractId,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: contractId,
    );
  }

  Future<void> sync(AppStore store) async {
    if (!_ready) return;

    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if ((request.id & 0x40000000) == 0) {
        await _plugin.cancel(id: request.id);
      }
    }
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows && !store.windowsRemindersEnabled) return;
    if (!isWindows && !store.phoneRemindersEnabled) return;

    final offsets = store.reminderOffsets;
    for (final contract in store.activeContracts) {
      final space = store.adSpaceFor(contract.adSpaceId);
      final customer = store.customerFor(contract.customerId);
      if (space == null) continue;
      final scheduledDates = <String>{};
      for (var index = 0; index < offsets.length; index++) {
        final days = offsets[index];
        final requestedDate = timezone.TZDateTime(
          timezone.local,
          contract.endDate.year,
          contract.endDate.month,
          contract.endDate.day - days,
          store.reminderTimeMinutes ~/ 60,
          store.reminderTimeMinutes % 60,
        );
        final workingDate = BusinessDayHelper.nextWorkingDay(
          requestedDate,
          store.workingDays,
        );
        final reminderDate = timezone.TZDateTime(
          timezone.local,
          workingDate.year,
          workingDate.month,
          workingDate.day,
          requestedDate.hour,
          requestedDate.minute,
        );
        final dateKey =
            '${workingDate.year}-${workingDate.month}-${workingDate.day}';
        if (!scheduledDates.add(dateKey)) continue;
        if (!reminderDate.isAfter(timezone.TZDateTime.now(timezone.local))) {
          continue;
        }
        final daysRemaining = BusinessDayHelper.daysRemaining(
          contract.endDate,
          reminderDate,
        );
        final dayText = switch (daysRemaining) {
          0 => 'bugün sona eriyor',
          > 0 => '$daysRemaining gün sonra sona eriyor',
          _ => '${daysRemaining.abs()} gün önce sona erdi',
        };
        final customerName = customer?.name ?? 'Kiracı';
        await _plugin.zonedSchedule(
          id: _notificationId(contract.id, index),
          title: 'Sözleşme bitişi yaklaşıyor',
          body: '${space.name} alanındaki $customerName sözleşmesi $dayText.',
          scheduledDate: reminderDate,
          notificationDetails: _notificationDetails(
            defaultTargetPlatform,
            contractId: contract.id,
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: contract.id,
        );
      }
    }
  }

  Future<void> showWindowsTestNotification() async {
    if (!_ready || defaultTargetPlatform != TargetPlatform.windows) return;
    await _plugin.show(
      id: 0x7ffffffe,
      title: 'RST Dolapdere bildirimi',
      body: 'Windows masaüstü bildirimleri etkinleştirildi.',
      notificationDetails: const NotificationDetails(
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.long,
        ),
      ),
    );
  }

  int _notificationId(String id, int offsetIndex) =>
      (_hashId(id) * 32) + offsetIndex;

  static int _snoozedNotificationId(String id) => 0x40000000 | _hashId(id);

  static int _hashId(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x00ffffff;
    }
    return hash;
  }
}
