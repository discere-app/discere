import 'dart:async';
import 'dart:io';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationPermissionHandler {
  const NotificationPermissionHandler();

  Future<PermissionStatus> status() {
    return Permission.notification.status;
  }

  Future<PermissionStatus> request() {
    return Permission.notification.request();
  }
}

class NotificationService {
  static final _log = Logger.forType(NotificationService);
  static const String _notificationPermissionRequestedKey =
      'notification_permission_requested';

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final SharedPreferences? _preferences;
  final NotificationPermissionHandler _permissionHandler;
  final Map<int, _OngoingProgressState> _ongoingProgressState = {};

  final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  NotificationService({
    SharedPreferences? preferences,
    NotificationPermissionHandler permissionHandler =
        const NotificationPermissionHandler(),
  }) : _preferences = preferences,
       _permissionHandler = permissionHandler;

  Future<void> initNotification() async {
    AndroidInitializationSettings initializationSettingsAndroid =
        const AndroidInitializationSettings('@mipmap/launcher_icon');

    var initializationSettingsIOS = const DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    var initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) async {
            selectNotificationStream.add(notificationResponse.payload);
          },
    );
  }

  Future<void> requestPermissions() async {
    final status = await _permissionHandler.status();
    if (_isPermissionGranted(status)) {
      return;
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      _markPermissionPromptHandled();
      _log.debug('Notification permission cannot be requested again: $status');
      return;
    }

    final alreadyRequested =
        _preferences?.getBool(_notificationPermissionRequestedKey) ?? false;
    if (alreadyRequested) {
      _log.debug(
        'Notification permission was already requested before and is still not granted.',
      );
      return;
    }

    _markPermissionPromptHandled();
    final result = await _permissionHandler.request();
    _log.debug('Notification permission result: $result');
  }

  /// Records that the user declined the in-app soft-ask, so
  /// [shouldPromptForPermission] won't offer it again on a later launch.
  Future<void> declinePermissionPrompt() async {
    _markPermissionPromptHandled();
  }

  Future<bool> shouldPromptForPermission() async {
    if (!Platform.isAndroid) return false;

    final status = await _permissionHandler.status();
    if (_isPermissionGranted(status)) {
      return false;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      _markPermissionPromptHandled();
      return false;
    }

    final alreadyRequested =
        _preferences?.getBool(_notificationPermissionRequestedKey) ?? false;
    return !alreadyRequested;
  }

  bool _isPermissionGranted(PermissionStatus status) {
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  void _markPermissionPromptHandled() {
    _preferences?.setBool(_notificationPermissionRequestedKey, true);
  }

  NotificationDetails notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'channelId',
        'channelName',
        importance: Importance.max,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  /// Shows a persistent, ongoing progress notification (Android only) for a
  /// long-running background task — e.g. deck enrichment. Repeated calls
  /// with the same [title]/[body]/[progressCompleted]/[progressTotal] are
  /// no-ops; calls within [minUpdateInterval] of the last *changed* update
  /// are throttled. Callers own all task-specific content (title/body text,
  /// channel identity) — this API only knows about notifications, not about
  /// what's being tracked.
  Future<void> showOngoingProgress({
    required int notificationId,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    required int progressCompleted,
    required int progressTotal,
    Duration minUpdateInterval = const Duration(milliseconds: 750),
  }) async {
    if (!Platform.isAndroid) return;
    final permissionStatus = await _permissionHandler.status();
    if (!_isPermissionGranted(permissionStatus)) {
      return;
    }

    final now = DateTime.now();
    final last = _ongoingProgressState[notificationId];
    if (last != null &&
        last.matches(title, body, progressCompleted, progressTotal)) {
      return;
    }
    if (last != null && now.difference(last.updatedAt) < minUpdateInterval) {
      return;
    }

    await notificationsPlugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          autoCancel: false,
          showWhen: false,
          category: AndroidNotificationCategory.progress,
          indeterminate: progressTotal <= 0,
          maxProgress: progressTotal <= 0 ? 0 : progressTotal,
          progress: progressTotal <= 0 ? 0 : progressCompleted,
        ),
      ),
    );
    _ongoingProgressState[notificationId] = _OngoingProgressState(
      title: title,
      body: body,
      progressCompleted: progressCompleted,
      progressTotal: progressTotal,
      updatedAt: now,
    );
  }

  Future<void> cancelOngoingProgress(int notificationId) async {
    if (!Platform.isAndroid) return;
    await notificationsPlugin.cancel(id: notificationId);
    _ongoingProgressState.remove(notificationId);
  }

  Future<void> showNotification({
    int id = 0,
    String? title,
    String? body,
    String? payLoad,
  }) async {
    return notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails(),
      payload: payLoad,
    );
  }

  /// Whether notifications may currently be posted at all.
  ///
  /// Exposed so a caller that is about to schedule a batch can ask once,
  /// rather than having every single schedule call re-check.
  Future<bool> hasPermission() async =>
      _isPermissionGranted(await _permissionHandler.status());

  /// Drops every scheduled notification. Callers that reschedule a whole
  /// series start here, since there is no way to tell which of the pending
  /// ones their previous run created.
  Future<void> cancelAllScheduled() => notificationsPlugin.cancelAll();

  /// Schedules one notification for [when]. Silently does nothing for a time
  /// already past — the caller computing a series does not have to special-
  /// case the current day.
  ///
  /// The id is derived from [when], so scheduling the same slot twice
  /// replaces it rather than producing two notifications.
  Future<void> scheduleAt({
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (when.isBefore(DateTime.now())) return;

    final scheduledDate = tz.TZDateTime.from(when, tz.local);
    _log.debug(
      'Scheduling notification for ${scheduledDate.toLocal().toIso8601String()}',
    );
    await notificationsPlugin.zonedSchedule(
      id: _generateNotificationId(when),
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  int _generateNotificationId(DateTime scheduledNotificationDateTime) {
    return scheduledNotificationDateTime.millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
  }
}

class _OngoingProgressState {
  final String title;
  final String body;
  final int progressCompleted;
  final int progressTotal;
  final DateTime updatedAt;

  const _OngoingProgressState({
    required this.title,
    required this.body,
    required this.progressCompleted,
    required this.progressTotal,
    required this.updatedAt,
  });

  bool matches(
    String title,
    String body,
    int progressCompleted,
    int progressTotal,
  ) {
    return this.title == title &&
        this.body == body &&
        this.progressCompleted == progressCompleted &&
        this.progressTotal == progressTotal;
  }
}
