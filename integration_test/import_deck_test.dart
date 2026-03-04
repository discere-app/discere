import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:discere/main.dart' as app;

/// Grant camera & notification permissions on Android via adb before launch
Future<void> _grantPermissions() async {
  const package = 'ch.feberle.discere';
  const permissions = [
    'android.permission.CAMERA',
    'android.permission.POST_NOTIFICATIONS',
  ];
  for (final perm in permissions) {
    await Process.run(
      'adb',
      ['shell', 'pm', 'grant', package, perm],
      runInShell: true,
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Try to avoid frame assertion issues by ignoring frame scheduling after test
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    await _grantPermissions();
  });

  group('Import Deck Page', () {
    testWidgets('can navigate to Import Deck and use Paste Text tab',
        (tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 1. Open FAB
      final fab = find.byKey(const ValueKey('main-fab'));
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pump(const Duration(milliseconds: 800));

      // 2. Tap Import Deck
      final importButton = find.text('Import Deck');
      expect(importButton, findsOneWidget);
      await tester.tap(importButton);
      await tester.pump(const Duration(seconds: 2));

      // 3. Check if Paste Text tab is active (it should be due to INTEGRATION_TEST flag)
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Import from Text'), findsOneWidget);

      // 4. Test invalid JSON error
      await tester.enterText(find.byType(TextField), 'invalid');
      await tester.tap(find.text('Import from Text'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Import failed'), findsOneWidget);

      // Final cleanup to try and avoid _pendingFrame
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
