import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'mocks.mocks.dart';
import 'dart:io';
import 'package:discere/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:discere/service/common/notification_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/persistence/database_helper.dart';

/// Global initialization for all integration tests.
/// - Ensures the binding is localized.
/// - Sets the frame policy to fullyLive for visual feedback.
/// - Grants necessary Android permissions via adb.
Future<void> initializeIntegrationTest() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  await grantManualPermissions();
}

/// Central helper to start the application in a stable state for integration tests.
/// - notificationService: Optional mock or real notification service.
/// - initialPrefs: Map of SharedPreferences keys/values to stub. Defaults to bypassing the Welcome dialog.
/// - withTestDeck: If true, automatically creates a 'Test Deck' after app startup.
Future<void> startApp(WidgetTester tester, {
  NotificationService? notificationService,
  Map<String, Object> initialPrefs = const {'has_seen_welcome_dialog': true},
  bool withTestDeck = false,
  String deckName = 'Test Deck',
  String species = 'Amphiprion ocellaris',
}) async {
  // 0. Ensure the binding is active for this frame (idempotent if already called in initializeIntegrationTest)
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 1. Stub SharedPreferences before app starts
  SharedPreferences.setMockInitialValues(initialPrefs);

  // 2. Start the app
  await app.main(notificationService: notificationService);

  // Allow the emulator some time to start the main loop correctly and for splash to remove
  await Future.delayed(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();

  // 3. Optional: Set standard screen size for consistency (disabled by default based on user feedback)
  // setScreenSize(tester);

  // 4. Initial pump to settle animations and dialogs

  // 4. Initial pump to settle animations and dialogs
  // Multi-phase settle to handle complex service initialization
  if (kDebugMode) debugPrint("startApp: settling UI...");
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  if (kDebugMode) debugPrint("startApp: UI settled.");

  // 5. Optionally create a test deck if needed
  if (withTestDeck) {
    await createTestDeck(tester, name: deckName, species: species);
    await tester.pumpAndSettle(const Duration(seconds: 1));
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
    debugPrint('-- FAKE_SHARE_PLATFORM: share called with text length: ${params.text?.length} --');
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
Future<void> createTestDeck(WidgetTester tester, {String name = 'Test Deck', String species = 'Amphiprion ocellaris'}) async {
  if (kDebugMode) debugPrint("createTestDeck: starting for $name...");
  // 1. Open FAB
  final fab = find.byKey(const ValueKey('main-fab'));
  await tester.tap(fab);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));

  // 2. Tap Create Deck
  final createButton = find.byIcon(Icons.create_new_folder_outlined);
  await tester.tap(createButton);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));

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
  await tester.pump(const Duration(seconds: 2));
  if (kDebugMode) debugPrint("createTestDeck: submitted.");

  // 6. Handle the new iNat Download Dialog (Skip by default for speed in tests)
  await dismissDownloadDialog(tester);
}

/// Sets a standard screen size for integration tests to prevent layout overflows
/// on small-screen CI/CD environments.
void setScreenSize(WidgetTester tester, {double width = 412, double height = 915}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
}

/// Skips the iNaturalist download dialog if it appears.
/// Uses a short polling loop to wait for the dialog to appear if it's slightly delayed.
Future<void> dismissDownloadDialog(WidgetTester tester) async {
  if (kDebugMode) debugPrint("dismissDownloadDialog: checking...");
  // Give it a substantial window to appear (handling network/service delays)
  // 75 loops * 200ms = 15 seconds max wait
  for (int i = 0; i < 75; i++) {
    final dialog = find.byKey(const Key('inat_download_dialog'));
    if (dialog.evaluate().isNotEmpty) {
      if (kDebugMode) debugPrint("dismissDownloadDialog: dialog found on attempt $i, skipping...");
      await tester.tap(find.byKey(const Key('inat_skip_button')));
      // Allow the dialog to close and the underlying UI to settle
      for (int p = 0; p < 5; p++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      return;
    }
    // Yield to the underlying event loop
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (kDebugMode) debugPrint("dismissDownloadDialog: no dialog appeared after 15s.");
}

/// Confirms the iNaturalist download dialog and waits for it to finish.
Future<void> confirmDownloadDialog(WidgetTester tester) async {
  final dialog = find.byKey(const Key('inat_download_dialog'));
  if (dialog.evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('inat_download_button')));
    await tester.pumpAndSettle(); // Start
    
    // Wait for the progress dialog to show the "Done" button
    final doneButton = find.byKey(const Key('inat_done_button'));
    // We might need a longer timeout for network/fetching
    await tester.pumpAndSettle(const Duration(seconds: 10));
    
    if (doneButton.evaluate().isNotEmpty) {
      await tester.tap(doneButton);
      await tester.pumpAndSettle();
    }
  }
}

/// Fully resets the application state for a clean test run.
/// - Deletes the user database.
/// - Clears SharedPreferences by resetting mock initial values.
Future<void> resetTestState() async {
  if (kDebugMode) debugPrint("resetTestState: clearing database and preferences...");
  await DatabaseHelper.deleteUserDatabase();
  SharedPreferences.setMockInitialValues({'has_seen_welcome_dialog': true});
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
      await Process.run(
        'adb',
        ['shell', 'pm', 'grant', package, perm],
        runInShell: true,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('-- WARNING: Failed to grant $perm via adb: $e --');
    }
  }
  // Short delay to let the system process the grant
  await Future.delayed(const Duration(milliseconds: 500));
}
