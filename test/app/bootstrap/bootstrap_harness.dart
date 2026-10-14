import 'dart:async';
import 'dart:io';

import 'package:discere/app/bootstrap/app_session.dart';
import 'package:discere/app/bootstrap/bootstrap_app.dart';
import 'package:discere/app/flashcard_app.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';

/// Old ID of Amphiprion ocellaris, which the fixture aliases to [newSpeciesId].
const oldSpeciesId = 'discere:fishbase_species:6509';
const newSpeciesId = 'discere:species:6002';

const fixturePath = 'test/fixtures/discere_reference_test.db';

/// Puts the reference-DB fixture where the app looks for it and creates an
/// empty user database next to it — created here rather than by
/// `DatabaseHelper` only for the full-text table this test host supports
/// (see [seedFtsTableForTestHost]). Run inside `tester.runAsync`.
Future<void> seedDatabases(Directory supportDir) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await File(fixturePath).copy(
    await ReferenceDatabaseProvisioner.resolveLocalPath(),
  );
  final userDb = await openDatabase(
    p.join(supportDir.path, 'discere_user.db'),
    version: UserDbSchema.version,
    onConfigure: seedFtsTableForTestHost,
    onCreate: UserDbSchema.create,
  );
  await userDb.close();
}

/// Preferences of an installed app at reference-DB [version], past every
/// first-run dialog and tutorial.
Map<String, Object> installedPreferences({int version = 1}) => {
  ReferenceDatabaseProvisioner.prefKeyVersion: version,
  ReferenceDatabaseProvisioner.prefKeySchemaVersion: 2,
  'has_seen_welcome_dialog': true,
  'has_seen_tutorial': true,
  'has_seen_deck_edit_tutorial': true,
  'has_seen_flashcard_tutorial': true,
  'has_seen_species_detail_tutorial': true,
  'has_seen_edit_deck_tutorial': true,
};

/// Pumps [BootstrapApp] with every HTTP request answered by [network] —
/// offline unless given. Run inside `tester.runAsync`.
Future<void> pumpBootstrapApp(
  WidgetTester tester, {
  http.Client? network,
}) async {
  final notifications = MockNotificationService();
  final selections = StreamController<String?>.broadcast();
  addTearDown(selections.close);
  when(notifications.selectNotificationStream).thenReturn(selections);
  final client = network ?? MockClientOffline();
  await tester.pumpWidget(
    BootstrapApp(
      processEnrichmentJobs: false,
      notificationService: notifications,
      httpClient: client,
      referenceDbDownloader: ReferenceDbDownloader(
        client: client,
        foregroundServiceKeeper: const NoopForegroundServiceKeeper(),
      ),
    ),
  );
}

/// Pumps until [condition] holds, with real time passing in between for the
/// file and database work. Run inside `tester.runAsync`.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
}) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    await tester.pump();
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for ${reason ?? 'the condition'}');
}

/// An HTTP client for which every host is unreachable.
class MockClientOffline extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 503);
}

/// Ends the session the running app was bootstrapped with and closes the
/// databases — what a restart does before it bootstraps again. Without it,
/// deferred setup still running would reopen the database after the test
/// is torn down. Run inside `tester.runAsync`.
Future<void> stopApp(WidgetTester tester) async {
  final app = find.byType(FlashcardApp);
  if (app.evaluate().isNotEmpty) {
    await Provider.of<AppSession>(tester.element(app), listen: false).stop();
  }
  await DatabaseHelper.close();
}
