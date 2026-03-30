import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../model/learning/flash_card_stat.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initNotification() async {

    AndroidInitializationSettings initializationSettingsAndroid =
        const AndroidInitializationSettings("@mipmap/ic_launcher");

    var initializationSettingsIOS = const DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    var initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
    await notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse:
            (NotificationResponse notificationResponse) async {});
  }

  Future<void> requestPermissions() async {

    var resolvePlatformSpecificImplementation =
        notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await resolvePlatformSpecificImplementation?.requestNotificationsPermission();
    await resolvePlatformSpecificImplementation?.requestExactAlarmsPermission();
  }

  NotificationDetails notificationDetails() {
    return const NotificationDetails(
        android: AndroidNotificationDetails('channelId', 'channelName',
            importance: Importance.max),
        iOS: DarwinNotificationDetails());
  }

  Future<void> showNotification(
      {int id = 0, String? title, String? body, String? payLoad}) async {
    return notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails(),
      payload: payLoad,
    );
  }

  Future<void> rescheduleAll({
    required List<FlashCardStat> allCards,
    required int preferredHour,
    int preferredMinute = 0,
    int daysAhead = 14,
    required String title,
    required String Function(int count) bodyBuilder,
  }) async {
    await notificationsPlugin.cancelAll();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int i = 0; i < daysAhead; i++) {
      final day = today.add(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));

      final int count;
      if (i == 0) {
        // Am ersten Tag (heute) zählen wir alle überfälligen Karten inkl. derer, die heute fällig werden.
        count = allCards.where((c) =>
          c.nextReviewDate != null &&
          c.nextReviewDate!.isBefore(nextDay)
        ).length;
      } else {
        // Für zukünftige Tage zählen wir nur die Karten, die spezifisch an diesem Tag fällig werden.
        count = allCards.where((c) =>
          c.nextReviewDate != null &&
          c.nextReviewDate!.isAfter(day) &&
          c.nextReviewDate!.isBefore(nextDay)
        ).length;
      }

      if (count == 0) continue;

      final scheduledTime = DateTime(
        day.year, day.month, day.day,
        preferredHour, preferredMinute,
      );

      // Nicht in der Vergangenheit planen (relevant für "heute")
      if (scheduledTime.isBefore(now)) continue;

      var tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
      int id = _generateNotificationId(scheduledTime);

      if (kDebugMode) {
        print('neue Daily Notification geplant: ${tzDateTime.toLocal().toIso8601String()} mit count $count');
      }

      await notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: bodyBuilder(count),
        scheduledDate: tzDateTime,
        notificationDetails: notificationDetails(),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
      );
    }
  }

  int _generateNotificationId(DateTime scheduledNotificationDateTime) {
    return scheduledNotificationDateTime.millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
  }
}
