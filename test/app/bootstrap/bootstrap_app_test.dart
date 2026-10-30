import 'dart:io';

import 'package:discere/app/bootstrap/bootstrap_app.dart';
import 'package:discere/app/flashcard_app.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap_harness.dart';


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
          packageInfo: installedPackage,
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

  testWidgets('the reference IDs of the user data are rewritten before the '
      'services that read them are built', (tester) async {
    final watchlist = await tester.runAsync(() async {
      await seedDatabases(supportDir);
      SharedPreferences.setMockInitialValues({
        ...installedPreferences(),
        WatchlistService.watchlistKey: [oldSpeciesId],
      });
      await pumpBootstrapApp(tester);
      final app = find.byType(FlashcardApp);
      await pumpUntil(tester, () => app.evaluate().isNotEmpty);
      return Provider.of<WatchlistService>(
        tester.element(app),
        listen: false,
      ).getSpecies();
    });
    await tester.runAsync(() => stopApp(tester));

    // The service reads the watchlist once, when it is built — had the
    // migration run after that, it would still hold the old ID.
    expect(watchlist, {newSpeciesId});
  });

  testWidgets('a start finishes installing a staged update an earlier start '
      'left half done, and applies its aliases', (tester) async {
    final (version, watchlist) = await tester.runAsync(() async {
      await seedDatabases(supportDir);
      // The earlier start moved the staged file into place (the fixture is
      // the new database) and stopped before stamping it or rewriting the
      // user data: only the metadata of the staging is left.
      await StagedReferenceDb(
        await ReferenceDatabaseProvisioner.resolveLocalPath(),
      ).writeMetadata(
        version: 2,
        schemaVersion: 2,
      );
      SharedPreferences.setMockInitialValues({
        ...installedPreferences(version: 1),
        ReferenceIdMigration.prefKeyAppliedVersion: 1,
        WatchlistService.watchlistKey: [oldSpeciesId],
      });
      await pumpBootstrapApp(tester);
      final app = find.byType(FlashcardApp);
      await pumpUntil(tester, () => app.evaluate().isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      return (
        prefs.getInt(ReferenceDatabaseProvisioner.prefKeyVersion),
        Provider.of<WatchlistService>(
          tester.element(app),
          listen: false,
        ).getSpecies(),
      );
    }) ?? (null, null);
    await tester.runAsync(() => stopApp(tester));

    expect(version, 2);
    expect(watchlist, {newSpeciesId});
  });
}
