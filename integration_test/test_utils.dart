import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'mocks.mocks.dart';
import 'package:discere/main.dart' as app;

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
  // 1. Open FAB
  final fab = find.byKey(const ValueKey('main-fab'));
  await tester.tap(fab);
  await tester.pumpAndSettle();

  // 2. Tap Create Deck
  final createButton = find.byIcon(Icons.create_new_folder_outlined);
  await tester.tap(createButton);
  await tester.pumpAndSettle();

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
  
  // 5. Submit
  final submitButton = find.byKey(const ValueKey('create_deck_submit_button'));
  await tester.scrollUntilVisible(
    submitButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(submitButton);
  await tester.pumpAndSettle();
}

/// Sets a standard screen size for integration tests to prevent layout overflows
/// on small-screen CI/CD environments.
void setScreenSize(WidgetTester tester, {double width = 450, double height = 800}) {
  final size = Size(width, height);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
}
