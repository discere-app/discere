import 'dart:async';
import 'dart:io';

import 'package:discere/app/bootstrap/bootstrap_app.dart';
import 'package:discere/app/flashcard_app.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';

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

  testWidgets('the reference IDs of the user data are rewritten before the '
      'services that read them are built', (tester) async {
    // Amphiprion ocellaris under its old ID; the fixture aliases it.
    const oldId = 'discere:fishbase_species:6509';
    const newId = 'discere:species:6002';
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final watchlist = await tester.runAsync(() async {
      await File('test/fixtures/discere_reference_test.db').copy(
        await ReferenceDatabaseProvisioner.resolveLocalPath(),
      );
      // Created here rather than by DatabaseHelper only for the full-text
      // table this test host supports (see seedFtsTableForTestHost).
      final userDb = await openDatabase(
        p.join(supportDir.path, 'discere_user.db'),
        version: UserDbSchema.version,
        onConfigure: seedFtsTableForTestHost,
        onCreate: UserDbSchema.create,
      );
      await userDb.close();
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeyVersion: 1,
        ReferenceDatabaseProvisioner.prefKeySchemaVersion:
            ReferenceDatabaseProvisioner.supportedSchemaVersion,
        WatchlistService.watchlistKey: [oldId],
      });

      final notifications = MockNotificationService();
      final selections = StreamController<String?>.broadcast();
      addTearDown(selections.close);
      when(notifications.selectNotificationStream).thenReturn(selections);
      final offline = MockClient((_) async => http.Response('offline', 503));
      await tester.pumpWidget(
        BootstrapApp(
          processEnrichmentJobs: false,
          notificationService: notifications,
          httpClient: offline,
          referenceDbDownloader: ReferenceDbDownloader(
            client: offline,
            foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
          ),
        ),
      );
      for (var attempt = 0; attempt < 200; attempt++) {
        await tester.pump();
        final app = find.byType(FlashcardApp);
        if (app.evaluate().isNotEmpty) {
          return Provider.of<WatchlistService>(
            tester.element(app),
            listen: false,
          ).getSpecies();
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });
    await tester.runAsync(DatabaseHelper.close);

    // The service reads the watchlist once, when it is built — had the
    // migration run after that, it would still hold the old ID.
    expect(watchlist, {newId});
  });
}
