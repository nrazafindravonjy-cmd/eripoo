import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../../../app/sync/background_sync.dart';
import '../../../core/i18n/app_language.dart';
import '../../../l10n/generated/app_localizations.dart';

/// What the reminders need from the phone: the notification permission
/// (Android 13+) and a periodic background check.
abstract interface class ReminderPlatform {
  /// True when notifications may be shown.
  Future<bool> requestPermission();
  Future<void> schedule();
  Future<void> cancel();
}

/// Android: `flutter_local_notifications` and WorkManager.
///
/// ⚠️ NOT VERIFIED on a device (permission dialog, notification display,
/// WorkManager timing under battery saving).
class AndroidReminderPlatform implements ReminderPlatform {
  static const uniqueName = 'eripoo.reminders';
  static const taskName = 'eripoo.reminders.periodic';
  static const _channelId = 'eripoo_missions';

  static Future<FlutterLocalNotificationsPlugin> _plugin() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return plugin;
  }

  @override
  Future<bool> requestPermission() async {
    final android = (await _plugin())
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> schedule() async {
    await Workmanager().initialize(backgroundSyncDispatcher);
    // Every few hours, no network needed; the policy shows at most one
    // reminder a day.
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(hours: 4),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  @override
  Future<void> cancel() => Workmanager().cancelByUniqueName(uniqueName);

  /// Shows the reminder, in the app's language (Malagasy by default).
  static Future<void> show(AppLanguage? language) async {
    final l10n = lookupAppLocalizations(
      Locale((language ?? AppLanguage.mg).name),
    );
    await (await _plugin()).show(
      id: 1,
      title: l10n.reminderTitle,
      body: l10n.reminderBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          l10n.reminderChannel,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }
}
