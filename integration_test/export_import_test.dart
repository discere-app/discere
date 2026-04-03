import 'dart:convert';

import 'package:discere/service/learning/decks_service.dart';
import 'package:discere/service/common/import_export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:discere/persistence/database_helper.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  late FakeSharePlatform fakeSharePlatform;


  setUp(() async {
    fakeSharePlatform = FakeSharePlatform.instance;
    fakeSharePlatform.reset();
    SharePlatform.instance = fakeSharePlatform;
    await DatabaseHelper.deleteUserDatabase();
  });

  tearDown(() async {
    await DatabaseHelper.close();
  });

  group('Export/Import Deck Integration', () {
    testWidgets('Export via Text -> Delete -> Import via Create Deck',
        (tester) async {
      final mockNotificationService = createMockNotificationService();

      await startApp(tester, notificationService: mockNotificationService);

      // 1. Create a deck to share
      await createTestDeck(tester, name: 'Share Test Deck');
      await tester.pumpAndSettle();

      // 2. Locate a deck to share
      final deckCardFinder = find.byType(Card);
      expect(deckCardFinder, findsWidgets,
          reason: 'Expected at least one deck card on home screen');

      final deckCard = deckCardFinder.first;
      final deckTitleFinder =
          find.descendant(of: deckCard, matching: find.byType(Text));
      expect(deckTitleFinder, findsWidgets,
          reason: 'Expected a text element in the card');

      final deckTitleElement = tester.widget<Text>(deckTitleFinder.first);
      final deckName = deckTitleElement.data!;
      debugPrint('Testing with deck: $deckName');

      // 2. Tap Share on the deck
      final shareButton = find.descendant(
        of: deckCard,
        matching: find.byIcon(Icons.share),
      );
      expect(shareButton, findsOneWidget,
          reason: 'Expected a share button on the deck card');
      await tester.tap(shareButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2)); // Wait for FutureBuilder

      // 3. Verify we are on Share Deck Page
      expect(find.text('Share Deck'), findsWidgets);

      // 4. Tap the native share icon (which triggers Share.share)
      // 4. Tap the "Species List" button
      debugPrint('-- TEST: tapping Species List --');
      await tester.tap(find.text('Species List'));
      debugPrint('-- TEST: pumping 1s --');
      await tester.pump(const Duration(seconds: 1));

      // 5. Verify the fake platform intercepted the text
      debugPrint('-- TEST: verifying text --');
      expect(fakeSharePlatform.lastSharedText, isNotNull,
          reason: 'Expected text to be shared');

      final exportedSpeciesList = fakeSharePlatform.lastSharedText!;
      expect(exportedSpeciesList.isNotEmpty, true);

      // Close share page
      debugPrint('-- TEST: tapping CloseButton --');
      await tester.tap(find.byType(CloseButton));
      debugPrint('-- TEST: pumpAndSettle after CloseButton --');
      await tester.pumpAndSettle();
      debugPrint('-- TEST: Close share page complete --');

      // 6. Delete the source deck via UI (testing confirmation dialog)
      debugPrint('-- TEST: finding deck card for deletion --');
      final targetDeckCard = find.ancestor(
        of: find.text(deckName),
        matching: find.byType(Dismissible),
      );
      expect(targetDeckCard, findsOneWidget, reason: 'Should find the deck card to delete');

      debugPrint('-- TEST: swiping to delete deck --');
      // Swipe from right to left to trigger delete
      await tester.drag(targetDeckCard, const Offset(-500, 0));
      await tester.pumpAndSettle();

      debugPrint('-- TEST: confirming deletion dialog --');
      final confirmButton = find.byKey(const Key('delete_deck_confirm_button'));
      expect(confirmButton, findsOneWidget, reason: 'Delete confirmation dialog should be visible');
      await tester.tap(confirmButton);
      
      debugPrint('-- TEST: pumpAndSettle after delete confirmation --');
      await tester.pumpAndSettle();
      
      debugPrint('-- TEST: verifying delete --');
      expect(find.text(deckName), findsNothing,
          reason: 'Deck should be deleted from UI');

      // 7. Import via Create Deck FAB
      final fab = find.byKey(const ValueKey('main-fab'));
      await tester.tap(fab);
      await tester.pumpAndSettle();

      final createOption = find.byIcon(Icons.create_new_folder_outlined);
      await tester.tap(createOption);
      await tester.pumpAndSettle();

      // 8. Fill Create Dialog
      await tester.enterText(
          find.byKey(const Key('create_deck_name_field')), '$deckName Imported');
      await tester.enterText(
          find.byKey(const Key('create_deck_description_field')), 'Imported via Text');

      // Need to scroll to find the multi-line text field for scientific names
      final speciesFieldFinder = find.byKey(const Key('create_deck_species_field'));
      await tester.scrollUntilVisible(
        speciesFieldFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(speciesFieldFinder, exportedSpeciesList);

      debugPrint('-- TEST: tapping create_deck_submit_button --');
      await tester.tap(find.byKey(const ValueKey('create_deck_submit_button')));
      
      // Give the service a moment to process before we even look for the dialog
      debugPrint('-- TEST: waiting for service processing... --');
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Dismiss the iNat download dialog (skip)
      debugPrint('-- TEST: dismissing iNat download dialog --');
      await dismissDownloadDialog(tester);
      
      // Final settle
      await tester.pumpAndSettle();

      // 9. Verify Deck was created successfully
      expect(find.text('$deckName Imported'), findsOneWidget);
    });

    testWidgets('Export via QR -> Extract JSON -> Delete -> Import via Service',
        (tester) async {
      final mockNotificationService = createMockNotificationService();

      await startApp(tester, notificationService: mockNotificationService);

      // 0. Create a deck to share
      await createTestDeck(tester, name: 'Share Test Deck');
      await tester.pumpAndSettle();

      final deckCardFinder = find.byType(Card);
      expect(deckCardFinder, findsWidgets);

      final deckCard = deckCardFinder.first;
      final deckTitleElement = tester.widget<Text>(
          find.descendant(of: deckCard, matching: find.byType(Text)).first);
      final deckName = deckTitleElement.data!;

      // 1. Open Share Page
      final shareButton = find.descendant(
        of: deckCard,
        matching: find.byIcon(Icons.share),
      );
      await tester.tap(shareButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2)); // Wait for FutureBuilder

      // 2. Extract JSON directly from the DecksService (as QrImageView data is private)
      final BuildContext context = tester.element(find.byType(MaterialApp));
      if (!context.mounted) return;
      final decksService = Provider.of<DecksService>(context, listen: false);
      final importExportService = Provider.of<ImportExportService>(context, listen: false);
      final decks = await decksService.getAllDecks();
      final deckToExport = decks.firstWhere((d) => d.name == deckName);
      final createDeck = await decksService.getCreateDeck(deckToExport.id!);
      final qrJsonData = jsonEncode(createDeck.toJson());

      expect(qrJsonData.isNotEmpty, true);

      // Close share page
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // 3. Delete Deck
      await decksService.deleteDeck(deckToExport.id!);
      await tester.pumpAndSettle();
      expect(find.text(deckName), findsNothing);

      // 4. Import directly via service (simulating a successful QR scan)
      await importExportService.importDeckFromJson(qrJsonData);

      // Trigger a refresh
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 5. Verify Deck is back
      expect(find.text(deckName), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    group('UI Sanity', () {
      testWidgets('Share page shows QR code', (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(tester, notificationService: mockNotificationService);

        // 0. Create a deck to share
        await createTestDeck(tester, name: 'Share Test Deck');
        await tester.pumpAndSettle();

        final shareButtonFinder = find.byIcon(Icons.share);
        expect(shareButtonFinder, findsWidgets);

        await tester.tap(shareButtonFinder.first);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2)); // Wait for FutureBuilder

        expect(find.byType(QrImageView), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
      });
    });
    testWidgets('Export via JSON Text -> Import via JSON Dialog', (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();

      // 1. Initial State
      await startApp(tester, notificationService: mockNotificationService);

      // 2. Create a deck to share
      await createTestDeck(tester, name: 'Share Test Deck');
      await tester.pumpAndSettle();

      // 3. Locate a deck to share
      final deckCardFinder = find.byType(Card);
      expect(deckCardFinder, findsWidgets);

      final deckCard = deckCardFinder.first;
      final deckTitleFinder = find.descendant(of: deckCard, matching: find.byType(Text));
      final deckTitleElement = tester.widget<Text>(deckTitleFinder.first);
      final originalDeckName = deckTitleElement.data!;

      // 3. Share Page -> Get JSON Text
      final shareIconFinder = find.descendant(of: deckCard, matching: find.byIcon(Icons.share));
      await tester.tap(shareIconFinder);
      await tester.pumpAndSettle();
      
      // Give the FutureBuilder in ShareDeckPage plenty of time to load the deck from DB
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Use text finder to be safer against multiple icons
      final jsonOptionFinder = find.widgetWithText(InkWell, 'JSON Text');
      debugPrint('-- TEST: searching for JSON Text button --');
      expect(jsonOptionFinder, findsOneWidget);
      
      await tester.scrollUntilVisible(
        jsonOptionFinder,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      
      debugPrint('-- TEST: tapping JSON Text button --');
      await tester.tap(jsonOptionFinder);
      await tester.pump(const Duration(seconds: 1));
      
      int attempts = 0;
      while (fakeSharePlatform.lastSharedText == null && attempts < 50) {
        if (attempts % 10 == 0) {
          debugPrint('-- TEST LOOP: waiting for lastSharedText (attempt $attempts) --');
        }
        await tester.pump(const Duration(milliseconds: 200));
        attempts++;
      }
      final success = (SharePlatform.instance as FakeSharePlatform).lastSharedText != null;
      debugPrint('-- TEST LOOP: finished after $attempts attempts, result: ${success ? 'SUCCESS' : 'FAILURE'} --');
      await tester.pumpAndSettle();

      expect(fakeSharePlatform.lastSharedText, isNotNull, 
          reason: 'Sharing via JSON should set lastSharedText. Check if scrolling/tapping reached the handler.');
      final exportedJson = fakeSharePlatform.lastSharedText!;

      // Close share page
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      // 4. Delete Original Deck via UI
      debugPrint('-- TEST: deleting original deck via UI --');
      final targetDeckCard = find.ancestor(
        of: find.text(originalDeckName),
        matching: find.byType(Dismissible),
      );
      await tester.drag(targetDeckCard, const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_deck_confirm_button')));
      await tester.pumpAndSettle();
      expect(find.text(originalDeckName), findsNothing);

      // 5. Open JSON Import Dialog
      await tester.tap(find.byKey(const ValueKey('main-fab')));
      await tester.pumpAndSettle();
      
      // Tap the "Import" option (represented by the scanner icon)
      await tester.tap(find.byIcon(Icons.qr_code_scanner));
      // Use pump() because Online tab has a spinner
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      
      // Switch to the JSON / File tab
      final jsonTab = find.byKey(const ValueKey('import-tab-json'));
      expect(jsonTab, findsOneWidget);
      await tester.tap(jsonTab);
      await tester.pumpAndSettle();

      // 6. Paste JSON and Import
      await tester.enterText(find.byType(TextField), exportedJson);
      // Tap "Import" button
      await tester.tap(find.byKey(const ValueKey('import-json-button')));
      
      debugPrint('-- TEST: waiting for JSON import processing... --');
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Dismiss the iNat download dialog (skip)
      debugPrint('-- TEST: dismissing iNat download dialog after JSON import --');
      await dismissDownloadDialog(tester);
      await tester.pumpAndSettle();

      // 7. Verify Deck Re-appeared
      expect(find.text(originalDeckName), findsOneWidget);
    });
  });
}
