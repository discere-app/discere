import 'dart:async';

import 'package:discere/app/bootstrap_app.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:timezone/data/latest.dart' as tz;

const _nativeSplashHardTimeout = Duration(seconds: 15);

Future<void> main({
  NotificationService? notificationService,
  bool processEnrichmentJobs = true,
}) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  tz.initializeTimeZones();

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
