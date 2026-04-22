import 'package:discere/app/bootstrap_app.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:timezone/data/latest.dart' as tz;

Future<void> main({
  NotificationService? notificationService,
  bool processEnrichmentJobs = true,
}) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  tz.initializeTimeZones();

  runApp(
    BootstrapApp(
      notificationService: notificationService,
      processEnrichmentJobs: processEnrichmentJobs,
    ),
  );
}
