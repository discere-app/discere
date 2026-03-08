import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:discere/main.dart' as app;
import 'package:mobile_scanner/mobile_scanner.dart';

/// Grant camera & notification permissions on Android via adb before launch
Future<void> _grantPermissions() async {
  if (!Platform.isAndroid) return;
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
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    await _grantPermissions();
  });

  group('Import Deck Page', () {
    testWidgets('can navigate to Import Deck and see QR Scanner UI',
        (tester) async {
      // Start the app
      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 1. Open FAB
      final fab = find.byKey(const ValueKey('main-fab'));
      expect(fab, findsOneWidget, reason: 'Main FAB not found');
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // 2. Tap Import Deck option in FAB menu
      final importOption = find.byIcon(Icons.qr_code_scanner);
      expect(importOption, findsWidgets,
          reason: 'Import Deck option not found in FAB menu');
      await tester.tap(importOption.first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      // 3. Verify we are on Import Deck Page (check AppBar title)
      expect(find.text('Import Deck'), findsWidgets,
          reason: 'Not on Import Deck page or title missing');

      // 4. Verify QR Scanner UI hints are present
      expect(find.byIcon(Icons.photo_library), findsOneWidget,
          reason: 'Gallery upload icon not found');
      expect(find.byType(MobileScanner), findsOneWidget,
          reason: 'QR scanner view not found');

      // Final cleanup
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
