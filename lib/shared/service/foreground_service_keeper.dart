import 'dart:io';
import 'dart:ui' as ui;

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the host process alive while long-running work is in flight —
/// background enrichment and the reference-database download both need this,
/// since either can span longer than the OS lets a backgrounded app run.
///
/// On Android the keeper starts a `flutter_foreground_task` foreground service
/// — a notification that prevents the OS from reaping the process. The plugin
/// also spawns a TaskHandler isolate, but that handler is intentionally a
/// no-op: all work continues in the UI isolate, which avoids the SQLite
/// writer-lock conflict a separate background isolate would cause on cold
/// start.
///
/// Multiple independent consumers may call [startKeepingAlive] /
/// [stopKeepingAlive] concurrently (e.g. enrichment and a reference-DB
/// download running at the same time) — implementations must reference-count
/// so the service only actually stops once every consumer is done with it.
abstract class ForegroundServiceKeeper {
  Future<void> initialize();

  /// Whether the keepalive foreground service is currently running. Always
  /// `false` on non-Android platforms.
  Future<bool> get isRunning;

  Future<void> startKeepingAlive();

  Future<void> stopKeepingAlive();

  /// Updates the title/text of the already-showing keepalive notification.
  /// Used to fold live progress into that single notification instead of
  /// showing a second, separate one. No-ops if the service isn't currently
  /// running.
  Future<void> updateNotificationContent({
    required String title,
    required String text,
  });
}

class NoopForegroundServiceKeeper implements ForegroundServiceKeeper {
  const NoopForegroundServiceKeeper();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> get isRunning async => false;

  @override
  Future<void> startKeepingAlive() async {}

  @override
  Future<void> stopKeepingAlive() async {}

  @override
  Future<void> updateNotificationContent({
    required String title,
    required String text,
  }) async {}
}

@pragma('vm:entry-point')
void foregroundKeeperTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopKeeperTaskHandler());
}

class _NoopKeeperTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class FlutterForegroundTaskKeeper implements ForegroundServiceKeeper {
  static final _log = Logger.forType(FlutterForegroundTaskKeeper);
  static const _channelId = 'discere.enrichment.keepalive';
  static const _channelName = 'Background enrichment';
  static const _channelDescription =
      'Keeps Discere running in the background while species enrichment or '
      'the reference database download finishes.';
  static String get _notificationTitle {
    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    return lang == 'de' ? 'Discere ist aktiv' : 'Discere is active';
  }

  static String get _notificationText {
    final lang = ui.PlatformDispatcher.instance.locale.languageCode;
    return lang == 'de' ? 'Wird im Hintergrund fortgesetzt …' : 'Continuing in the background …';
  }

  bool _initialized = false;

  // Reference count across independent consumers (enrichment, reference-DB
  // download) sharing one instance — the service must stay up until all of
  // them are done, and stopKeepingAlive() from one must not cut off another.
  int _activeCount = 0;

  bool get _isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> initialize() async {
    if (_initialized || !_isSupported) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> get isRunning async {
    if (!_isSupported) return false;
    return FlutterForegroundTask.isRunningService;
  }

  @override
  Future<void> startKeepingAlive() async {
    if (!_isSupported) return;
    _activeCount++;
    if (!_initialized) {
      await initialize();
    }
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    final result = await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: _notificationTitle,
      notificationText: _notificationText,
      callback: foregroundKeeperTaskCallback,
    );
    if (result is ServiceRequestFailure) {
      _log.warn('Foreground keeper start failed: ${result.error}');
    } else {
      _log.debug('Foreground keeper started');
    }
  }

  @override
  Future<void> stopKeepingAlive() async {
    if (!_isSupported) return;
    if (_activeCount > 0) _activeCount--;
    if (_activeCount > 0) {
      // Another consumer still needs the service alive.
      return;
    }
    if (!await FlutterForegroundTask.isRunningService) {
      return;
    }
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      _log.warn('Foreground keeper stop failed: ${result.error}');
    } else {
      _log.debug('Foreground keeper stopped');
    }
  }

  @override
  Future<void> updateNotificationContent({
    required String title,
    required String text,
  }) async {
    if (!_isSupported) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    final result = await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
    if (result is ServiceRequestFailure) {
      _log.warn('Foreground keeper content update failed: ${result.error}');
    }
  }
}
