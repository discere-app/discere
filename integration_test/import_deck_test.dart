import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discere/persistence/database_helper.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  tearDown(() async {
    await DatabaseHelper.close();
  });

  group('Import Deck Page', () {
    testWidgets('can navigate to Import Deck and see QR Scanner UI',
        (tester) async {
      final mockNotificationService = createMockNotificationService();

      // Start the app
      await startApp(tester, notificationService: mockNotificationService);

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
      // Use pump() instead of pumpAndSettle() because the Online tab shows a loading spinner
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      
      // 3. Switch to Scanner Tab (Online is default)
      final scannerTab = find.byKey(const ValueKey('import-tab-scanner'));
      expect(scannerTab, findsOneWidget);
      await tester.tap(scannerTab);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      // 3. Verify we are on Import Deck Page (check AppBar title)
      expect(find.byKey(const Key('import_deck_page_title')), findsWidgets,
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
