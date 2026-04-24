import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:discere/enrichment/service/enrichment_status_presenter.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/enrichment_progress_status.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/logger.dart';

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
  static const int _enrichmentNotificationId = 17765374;
  static const String _enrichmentChannelId = 'enrichment_progress';
  static const String _enrichmentChannelName = 'Deck enrichment';
  static const String _enrichmentChannelDescription =
      'Shows live progress while deck enrichment is running.';
  static const Duration _enrichmentNotificationMinUpdateInterval = Duration(
    milliseconds: 750,
  );

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final SharedPreferences? _preferences;
  final NotificationPermissionHandler _permissionHandler;
  INatEnrichmentStatus? _lastEnrichmentNotificationStatus;
  DateTime? _lastEnrichmentNotificationAt;

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
        const AndroidInitializationSettings("@mipmap/launcher_icon");

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
    await _createAndroidChannels();
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

  Future<void> _createAndroidChannels() async {
    final androidPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _enrichmentChannelId,
        _enrichmentChannelName,
        description: _enrichmentChannelDescription,
        importance: Importance.low,
      ),
    );
  }

  Future<void> showEnrichmentProgress(INatEnrichmentStatus status) async {
    if (!Platform.isAndroid) return;
    final permissionStatus = await _permissionHandler.status();
    if (!_isPermissionGranted(permissionStatus)) {
      return;
    }

    final now = DateTime.now();
    final lastStatus = _lastEnrichmentNotificationStatus;
    final lastUpdateAt = _lastEnrichmentNotificationAt;
    final shouldThrottle =
        lastStatus != null &&
        lastUpdateAt != null &&
        now.difference(lastUpdateAt) <
            _enrichmentNotificationMinUpdateInterval &&
        lastStatus.phase == status.phase &&
        lastStatus.total == status.total &&
        lastStatus.activeDeckCount == status.activeDeckCount &&
        lastStatus.readyDeckCount == status.readyDeckCount &&
        lastStatus.totalDeckCount == status.totalDeckCount &&
        status.completed < status.total;
    if (shouldThrottle) {
      return;
    }

    final locale = PlatformDispatcher.instance.locale;
    final loc = lookupAppLocalizations(
      locale.languageCode == 'de' ? const Locale('de') : const Locale('en'),
    );
    final title = formatEnrichmentTitle(loc, status);
    final readySummary = formatEnrichmentReadySummary(loc, status);
    final detail = formatEnrichmentDetail(loc, status);
    final body = '$readySummary - $detail';
    final progressTotal = status.isRunning
        ? status.total
        : status.totalDeckCount;
    final progressCompleted = status.isRunning
        ? status.completed
        : status.readyDeckCount;

    await notificationsPlugin.show(
      id: _enrichmentNotificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _enrichmentChannelId,
          _enrichmentChannelName,
          channelDescription: _enrichmentChannelDescription,
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
    _lastEnrichmentNotificationStatus = status;
    _lastEnrichmentNotificationAt = now;
  }

  Future<void> cancelEnrichmentProgress() async {
    if (!Platform.isAndroid) return;
    await notificationsPlugin.cancel(id: _enrichmentNotificationId);
    _lastEnrichmentNotificationStatus = null;
    _lastEnrichmentNotificationAt = null;
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

  Future<void> rescheduleAll({
    required List<DateTime?> cardDueDates,
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
        count = cardDueDates
            .where((date) => date != null && date.isBefore(nextDay))
            .length;
      } else {
        // Für zukünftige Tage zählen wir nur die Karten, die spezifisch an diesem Tag fällig werden.
        count = cardDueDates
            .where(
              (date) =>
                  date != null && date.isAfter(day) && date.isBefore(nextDay),
            )
            .length;
      }

      if (count == 0) continue;

      final scheduledTime = DateTime(
        day.year,
        day.month,
        day.day,
        preferredHour,
        preferredMinute,
      );

      // Nicht in der Vergangenheit planen (relevant für "heute")
      if (scheduledTime.isBefore(now)) continue;

      var tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);
      int id = _generateNotificationId(scheduledTime);

      _log.debug(
        'neue Daily Notification geplant: ${tzDateTime.toLocal().toIso8601String()} mit count $count',
      );

      await notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: bodyBuilder(count),
        scheduledDate: tzDateTime,
        notificationDetails: notificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: AppConstants.notificationPayloadDailyReview,
      );
    }
  }

  int _generateNotificationId(DateTime scheduledNotificationDateTime) {
    return scheduledNotificationDateTime.millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
  }
}
