import 'dart:io';

import 'package:discere/app/bootstrap/bootstrap_app.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const nativeSplash = MethodChannel('flutter_native_splash');
  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('bootstrap_app_test');
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, (call) async {
      return supportDir.path;
    });
    messenger.setMockMethodCallHandler(nativeSplash, (call) async => null);
  });

  tearDown(() async {
    Logger.configurePersistence(enabled: false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, null);
    messenger.setMockMethodCallHandler(nativeSplash, null);
    await supportDir.delete(recursive: true);
  });

  testWidgets('a failed reference database fetch on first launch lands in '
      'the diagnostics log file', (tester) async {
    // No local copy and an unreachable manifest: the first-launch path fails
    // before any database exists.
    final downloader = ReferenceDbDownloader(
      client: MockClient((_) async => http.Response('unavailable', 503)),
      foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
    );

    final logged = await tester.runAsync(() async {
      await tester.pumpWidget(
        BootstrapApp(
          processEnrichmentJobs: false,
          referenceDbDownloader: downloader,
        ),
      );
      final logFile = DiagnosticsLogFile();
      for (var attempt = 0; attempt < 100; attempt++) {
        final content = await logFile.readAll();
        if (content.isNotEmpty) return content;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return '';
    });

    expect(logged, contains('warning [bootstrap] Reference DB fetch failed'));
  });
}
