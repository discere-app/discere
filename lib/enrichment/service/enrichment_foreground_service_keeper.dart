import 'dart:io';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the host process alive while background enrichment is in flight.
///
/// On Android the keeper starts a `flutter_foreground_task` foreground service
/// — a notification that prevents the OS from reaping the process. The plugin
/// also spawns a TaskHandler isolate, but that handler is intentionally a
/// no-op: all enrichment work continues in the UI isolate, which avoids the
/// SQLite writer-lock conflict that the previous Workmanager-based design
/// caused on cold start.
abstract class EnrichmentForegroundServiceKeeper {
  Future<void> initialize();

  Future<void> startKeepingAlive();

  Future<void> stopKeepingAlive();
}

class NoopEnrichmentForegroundServiceKeeper
    implements EnrichmentForegroundServiceKeeper {
  const NoopEnrichmentForegroundServiceKeeper();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startKeepingAlive() async {}

  @override
  Future<void> stopKeepingAlive() async {}
}

@pragma('vm:entry-point')
void enrichmentKeeperTaskCallback() {
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

class FlutterForegroundTaskEnrichmentKeeper
    implements EnrichmentForegroundServiceKeeper {
  static final _log = Logger.forType(FlutterForegroundTaskEnrichmentKeeper);
  static const _channelId = 'discere.enrichment.keepalive';
  static const _channelName = 'Background enrichment';
  static const _channelDescription =
      'Keeps Discere running in the background while species enrichment '
      'finishes.';
  static const _notificationTitle = 'Discere ist aktiv';
  static const _notificationText = 'Hintergrund-Enrichment läuft …';

  bool _initialized = false;

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
  Future<void> startKeepingAlive() async {
    if (!_isSupported) return;
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
      callback: enrichmentKeeperTaskCallback,
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
}
