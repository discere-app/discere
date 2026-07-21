import 'dart:async';

import 'package:discere/app/bootstrap_app.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:timezone/data/latest.dart' as tz;

const _nativeSplashHardTimeout = Duration(seconds: 15);

Future<void> main({
  NotificationService? notificationService,
  bool processEnrichmentJobs = true,
}) async {
  // First line of Dart execution for this isolate/engine instance. If a
  // future engine restart (e.g. Android tearing down and recreating the
  // Activity while backgrounded) hangs before producing any other log line,
  // the absence of this line pinpoints the isolate never actually started —
  // as opposed to hanging somewhere inside bootstrap.
  Logger.debug('main', 'Dart entrypoint reached');
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Logged independently of BootstrapApp/INatEnrichmentQueueService's own
  // lifecycle observer (which only attaches once bootstrap — and enrichment
  // queue initialization — has completed) so lifecycle transitions are
  // visible even if the app hangs during startup itself.
  widgetsBinding.addObserver(_AppLifecycleObserver());
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  tz.initializeTimeZones();

  // App-wide portrait lock; the fullscreen image viewer temporarily lifts
  // this to allow landscape while it's open (see FullscreenImageViewer).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Belt-and-suspenders: BootstrapApp removes the native splash on its first
  // frame. This timer guarantees the splash is removed even if the engine
  // never reaches that frame (e.g. plugin init deadlock). No-op in the happy
  // path because remove() is idempotent.
  Timer(_nativeSplashHardTimeout, () {
    try {
      FlutterNativeSplash.remove();
    } catch (_) {
      // Already removed — fine.
    }
  });

  runApp(
    BootstrapApp(
      notificationService: notificationService,
      processEnrichmentJobs: processEnrichmentJobs,
    ),
  );
}

class _AppLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Logger.debug('main', 'Lifecycle state changed: $state');
    if (state == AppLifecycleState.detached) {
      // This engine is being torn down (e.g. Android destroying the
      // Activity under memory pressure while the enrichment foreground
      // service keeps the process itself alive). sqflite's native database
      // handle is a process-wide singleton keyed by path, not scoped to
      // this isolate — if a later engine in the same process opens the same
      // path before this one releases it, that open can hang indefinitely.
      unawaited(DatabaseHelper.close());
    }
  }
}
