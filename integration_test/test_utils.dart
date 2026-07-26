import 'dart:async';
import 'dart:io';

import 'package:discere/main.dart' as app;
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mockito/mockito.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mocks.mocks.dart';

const integrationTestTimeout = Timeout(Duration(minutes: 2));

// Arbitrary — only needs to be a valid version. The background update check
// this triggers on subsequent startApp() calls always fails fast (and fails
// open, keeping the seeded fixture) thanks to _FastFailHttpOverrides below,
// so no real manifest/version ever gets compared against this.
const _fixtureReferenceDbVersion = 1;

/// Copies the bundled reference-DB test fixture (a small, curated species
/// subset — see etl/scripts/build_test_fixture.sh) to the path
/// ReferenceDatabaseProvisioner expects, so integration tests never need a
/// real network download.
Future<void> _seedReferenceDb() async {
  final data = await rootBundle.load(
    'test/fixtures/discere_reference_test.db',
  );
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
  await File(path).parent.create(recursive: true);
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<void> safePumpAndSettle(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 100),
  Duration timeout = const Duration(seconds: 5),
  int fallbackPumps = 10,
}) async {
  try {
    await tester.pumpAndSettle(step, EnginePhase.sendSemanticsUpdate, timeout);
  } on FlutterError catch (error) {
    final message = error.toString();
    if (!message.contains('pumpAndSettle timed out')) {
      rethrow;
    }
    if (kDebugMode) {
      debugPrint(
        'safePumpAndSettle: timed out after $timeout, falling back to $fallbackPumps manual pumps.',
      );
    }
    for (var i = 0; i < fallbackPumps; i++) {
      await tester.pump(step);
    }
  }
}

/// Forces all HTTP connections to fail quickly in tests.
/// Background operations like image downloads won't block the test loop.
class _FastFailHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionTimeout = const Duration(milliseconds: 50);
  }
}

/// Global initialization for all integration tests.
/// - Ensures the binding is localized.
/// - Sets the frame policy to fullyLive for visual feedback.
/// - Grants necessary Android permissions via adb.
/// - Overrides HTTP to fail fast so background downloads don't block tests.
Future<void> initializeIntegrationTest() async {
  HttpOverrides.global = _FastFailHttpOverrides();
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  await grantManualPermissions();
}

/// Central helper to start the application in a stable state for integration tests.
/// - notificationService: Optional mock or real notification service.
/// - initialPrefs: Map of SharedPreferences keys/values to stub. Defaults to bypassing the Welcome dialog.
/// - withTestDeck: If true, automatically creates a 'Test Deck' after app startup.
Future<void> startApp(
  WidgetTester tester, {
  NotificationService? notificationService,
  Map<String, Object> initialPrefs = const {
    'has_seen_welcome_dialog': true,
    'has_seen_tutorial': true,
    'has_seen_flashcard_tutorial': true,
    'has_seen_species_detail_tutorial': true,
    'language': 1,
    ReferenceDatabaseProvisioner.prefKeyVersion: _fixtureReferenceDbVersion,
  },
  bool withTestDeck = false,
  String deckName = 'Test Deck',
  String species = 'Amphiprion ocellaris',
  bool processEnrichmentJobs = false,
}) async {
  // 0. Ensure the binding is active for this frame (idempotent if already called in initializeIntegrationTest)
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 1. Stub SharedPreferences before app starts
  SharedPreferences.setMockInitialValues(initialPrefs);

  // 1.5. Seed the small reference-DB test fixture at the path
  // ReferenceDatabaseProvisioner expects, so the app finds a local copy
  // immediately and never attempts a real network download. This runs
  // on-device (this whole file executes inside the compiled app when run via
  // `flutter test integration_test/... -d <device>`), so the fixture must be
  // read via rootBundle rather than a host filesystem path.
  await _seedReferenceDb();

  // 2. Start the app
  await app.main(
    notificationService: notificationService,
    processEnrichmentJobs: processEnrichmentJobs,
  );

  // Allow the emulator some time to start the main loop correctly and for splash to remove
  await Future.delayed(const Duration(milliseconds: 500));

  // 3. Optional: Set standard screen size for consistency (disabled by default based on user feedback)
  // setScreenSize(tester);

  // 4. Settle animations and dialogs after app startup
  if (kDebugMode) debugPrint('startApp: settling UI...');
  await safePumpAndSettle(tester);
  if (kDebugMode) debugPrint('startApp: UI settled.');

  // 5. Optionally create a test deck if needed
  if (withTestDeck) {
    await createTestDeck(tester, name: deckName, species: species);
    await tester.pump(const Duration(seconds: 1));
    await dismissDownloadDialog(tester);
  }
}

/// A helper to create a MockNotificationService with standard stubs
/// already configured (initNotification, requestPermissions, selectNotificationStream).
MockNotificationService createMockNotificationService() {
  final mock = MockNotificationService();
  final controller = StreamController<String?>.broadcast();
  when(mock.selectNotificationStream).thenReturn(controller);
  when(mock.initNotification()).thenAnswer((_) async {});
  when(mock.requestPermissions()).thenAnswer((_) async {});
  when(mock.shouldPromptForPermission()).thenAnswer((_) async => false);
  when(
    mock.showOngoingProgress(
      notificationId: anyNamed('notificationId'),
      channelId: anyNamed('channelId'),
      channelName: anyNamed('channelName'),
      channelDescription: anyNamed('channelDescription'),
      title: anyNamed('title'),
      body: anyNamed('body'),
      progressCompleted: anyNamed('progressCompleted'),
      progressTotal: anyNamed('progressTotal'),
      minUpdateInterval: anyNamed('minUpdateInterval'),
    ),
  ).thenAnswer((_) async {});
  when(
    mock.cancelOngoingProgress(any),
  ).thenAnswer((_) async {});
  when(
    mock.rescheduleAll(
      cardDueDates: anyNamed('cardDueDates'),
      preferredHour: anyNamed('preferredHour'),
      preferredMinute: anyNamed('preferredMinute'),
      daysAhead: anyNamed('daysAhead'),
      title: anyNamed('title'),
      bodyBuilder: anyNamed('bodyBuilder'),
    ),
  ).thenAnswer((_) async {});
  when(
    mock.showNotification(
      id: anyNamed('id'),
      title: anyNamed('title'),
      body: anyNamed('body'),
      payLoad: anyNamed('payLoad'),
    ),
  ).thenAnswer((_) async {});
  return mock;
}

/// A shared singleton fake platform implementation to intercept Share.share calls
/// across all integration test files.
class FakeSharePlatform extends SharePlatform {
  static final FakeSharePlatform instance = FakeSharePlatform._internal();

  FakeSharePlatform._internal();

  String? lastSharedText;
  String? lastSubject;

  @override
  Future<ShareResult> share(ShareParams params) async {
    debugPrint(
      '-- FAKE_SHARE_PLATFORM: share called with text length: ${params.text?.length} --',
    );
    lastSharedText = params.text;
    lastSubject = params.subject;
    return const ShareResult('success', ShareResultStatus.success);
  }

  void reset() {
    lastSharedText = null;
    lastSubject = null;
  }
}

/// A helper to create a deck named [name] with [species] in it.
/// Assumes we are on the Home screen.
Future<void> createTestDeck(
  WidgetTester tester, {
  String name = 'Test Deck',
  String species = 'Amphiprion ocellaris',
}) async {
  if (kDebugMode) debugPrint('createTestDeck: starting for $name...');
  // 1. Open FAB
  final fab = find.byKey(const ValueKey('main-fab'));
  await tester.tap(fab);
  await safePumpAndSettle(tester);

  // 2. Tap Create Deck
  final createButton = find.byIcon(Icons.create_new_folder_outlined);
  await tester.tap(createButton);
  await safePumpAndSettle(tester);

  // 3. Enter Name
  await tester.enterText(find.byKey(const Key('create_deck_name_field')), name);

  // 4. Enter Species (Scroll if needed)
  final speciesFieldFinder = find.byKey(const Key('create_deck_species_field'));
  await tester.scrollUntilVisible(
    speciesFieldFinder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(speciesFieldFinder, species);
  await tester.pump(const Duration(seconds: 1)); // Wait for search

  // 5. Submit
  final submitButton = find.byKey(const ValueKey('create_deck_submit_button'));
  await tester.scrollUntilVisible(
    submitButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(submitButton);
  // Use pump() not pumpAndSettle() — the submit button shows a CircularProgressIndicator
  // (infinite animation) while creating, which prevents pumpAndSettle() from settling.
  await tester.pump(const Duration(milliseconds: 500));
  if (kDebugMode) debugPrint('createTestDeck: submitted.');

  // 6. Handle the new iNat Download Dialog (Skip by default for speed in tests)
  await dismissDownloadDialog(tester);
}

/// Sets a standard screen size for integration tests to prevent layout overflows
/// on small-screen CI/CD environments.
void setScreenSize(
  WidgetTester tester, {
  double width = 412,
  double height = 915,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
}

/// Closes the import result dialog if it appears.
///
/// Importing through the import page now shows this dialog before the optional
/// enrichment prompt. Closing it declines enrichment and returns to the deck list.
Future<void> dismissImportResultDialog(WidgetTester tester) async {
  if (kDebugMode) debugPrint('dismissImportResultDialog: checking...');
  for (int i = 0; i < 20; i++) {
    final closeButton = find.byKey(const Key('import_result_close_button'));
    if (closeButton.evaluate().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'dismissImportResultDialog: dialog found on attempt $i, closing...',
        );
      }
      await tester.tap(closeButton);
      await safePumpAndSettle(tester);
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (kDebugMode) {
    debugPrint('dismissImportResultDialog: no dialog appeared after 4s.');
  }
}

/// Skips import/enrichment follow-up dialogs if they appear.
/// Uses a short polling loop to wait for dialogs if they are slightly delayed.
Future<void> dismissDownloadDialog(WidgetTester tester) async {
  if (kDebugMode) debugPrint('dismissDownloadDialog: checking...');
  for (int i = 0; i < 20; i++) {
    final importResultCloseButton = find.byKey(
      const Key('import_result_close_button'),
    );
    if (importResultCloseButton.evaluate().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'dismissDownloadDialog: import result found on attempt $i, closing...',
        );
      }
      await tester.tap(importResultCloseButton);
      await safePumpAndSettle(tester);
      return;
    }

    final dialog = find.byKey(const Key('inat_download_dialog'));
    if (dialog.evaluate().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'dismissDownloadDialog: dialog found on attempt $i, skipping...',
        );
      }
      await tester.tap(find.byKey(const Key('inat_skip_button')));
      await safePumpAndSettle(tester);
      return;
    }

    final backOnHome =
        find.byKey(const ValueKey('main-fab')).evaluate().isNotEmpty &&
        find.byKey(const Key('create_deck_name_field')).evaluate().isEmpty;
    if (backOnHome) {
      if (kDebugMode) {
        debugPrint(
          'dismissDownloadDialog: back on home without dialog on attempt $i.',
        );
      }
      return;
    }

    await tester.pump(const Duration(milliseconds: 200));
  }
  if (kDebugMode) {
    debugPrint('dismissDownloadDialog: no dialog appeared after 4s.');
  }
}

/// Confirms the iNaturalist download dialog and waits for it to finish.
Future<void> confirmDownloadDialog(WidgetTester tester) async {
  final dialog = find.byKey(const Key('inat_download_dialog'));
  if (dialog.evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('inat_download_button')));
    await safePumpAndSettle(tester); // Start

    // Wait for the progress dialog to show the "Done" button
    final doneButton = find.byKey(const Key('inat_done_button'));
    // We might need a longer timeout for network/fetching
    await safePumpAndSettle(
      tester,
      timeout: const Duration(seconds: 10),
      fallbackPumps: 20,
    );

    if (doneButton.evaluate().isNotEmpty) {
      await tester.tap(doneButton);
      await safePumpAndSettle(tester);
    }
  }
}

/// Fully resets the application state for a clean test run.
/// - Deletes the user database.
/// - Clears SharedPreferences by resetting mock initial values.
Future<void> resetTestState() async {
  if (kDebugMode) {
    debugPrint('resetTestState: clearing database and preferences...');
  }
  await DatabaseHelper.deleteUserDatabase();
  SharedPreferences.setMockInitialValues({
    'has_seen_welcome_dialog': true,
    'has_seen_tutorial': true,
    'has_seen_flashcard_tutorial': true,
    'language': 1,
    ReferenceDatabaseProvisioner.prefKeyVersion: _fixtureReferenceDbVersion,
  });
}

/// Grant camera & notification permissions on Android via adb before launch.
/// This prevents tests from hanging on permission dialogs.
Future<void> grantManualPermissions() async {
  if (!Platform.isAndroid) return;
  const package = 'ch.feberle.discere';
  const permissions = [
    'android.permission.CAMERA',
    'android.permission.POST_NOTIFICATIONS',
  ];
  for (final perm in permissions) {
    try {
      await Process.run('adb', [
        'shell',
        'pm',
        'grant',
        package,
        perm,
      ], runInShell: true).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('-- WARNING: Failed to grant $perm via adb: $e --');
    }
  }
  // Short delay to let the system process the grant
  await Future.delayed(const Duration(milliseconds: 500));
}
