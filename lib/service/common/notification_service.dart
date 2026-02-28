import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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

  Future<void> scheduleNotification(
      {String? title,
      String? body,
      String? payLoad,
      required DateTime scheduledNotificationDateTime}) async {
    DateTime roundedNotificationDateTime = DateTime(
            scheduledNotificationDateTime.year,
            scheduledNotificationDateTime.month,
            scheduledNotificationDateTime.day,
            scheduledNotificationDateTime.hour,
            (scheduledNotificationDateTime.minute ~/ 30) *
                30) // Rundet auf das nächste 30-Minuten-Intervall
        .add(const Duration(minutes: 30));

    int id = _generateNotificationId(roundedNotificationDateTime);

    List<PendingNotificationRequest> activeNotifications =
        await notificationsPlugin.pendingNotificationRequests();

    bool notificationExists =
        activeNotifications.any((notification) => notification.id == id);

    if (!notificationExists) {
      var tzDateTime =
          tz.TZDateTime.from(roundedNotificationDateTime, tz.local);
      if (kDebugMode) {
        print(
            'neue Notification geplant: ${tzDateTime.toLocal().toIso8601String()}');
      }

      return notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
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
