import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

void main() {
  initializeIntegrationTest();



  group('Import Deck Page', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'can navigate to Import Deck and see QR Scanner UI',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        // Start the app
        await startApp(tester, notificationService: mockNotificationService);

        // 1. Open FAB
        final fab = find.byKey(const ValueKey('main_fab'));
        expect(fab, findsOneWidget, reason: 'Main FAB not found');
        await tester.tap(fab);
        await safePumpAndSettle(tester);

        // 2. Tap Import Deck option in FAB menu
        final importOption = find.byIcon(Icons.download_for_offline_outlined);
        expect(
          importOption,
          findsWidgets,
          reason: 'Import Deck option not found in FAB menu',
        );
        await tester.tap(importOption.first);
        // Use pump() instead of pumpAndSettle() because the Online tab shows a loading spinner
        await tester.pump(const Duration(milliseconds: 500));
        await safePumpAndSettle(tester);

        // 3. Switch to Scanner Tab (Online is default)
        final scannerTab = find.byKey(const ValueKey('import_tab_scanner'));
        expect(scannerTab, findsOneWidget);
        await tester.tap(scannerTab);
        await safePumpAndSettle(tester);
        await tester.pump(const Duration(seconds: 2));

        // 3. Verify we are on Import Deck Page (check AppBar title)
        expect(
          find.byKey(const Key('import_deck_page_title')),
          findsWidgets,
          reason: 'Not on Import Deck page or title missing',
        );

        // 4. Verify QR Scanner UI hints are present
        expect(
          find.byIcon(Icons.photo_library),
          findsOneWidget,
          reason: 'Gallery upload icon not found',
        );
        expect(
          find.byType(MobileScanner),
          findsOneWidget,
          reason: 'QR scanner view not found',
        );

        await safePumpAndSettle(tester);
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'a pasted species list becomes a deck via Create Deck',
      (tester) async {
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
        );

        await tester.tap(find.byKey(const ValueKey('main_fab')));
        await safePumpAndSettle(tester);
        await tester.tap(
          find.byIcon(Icons.download_for_offline_outlined).first,
        );
        // pump() first: the Online tab opens with a loading spinner.
        await tester.pump(const Duration(milliseconds: 500));
        await safePumpAndSettle(tester);
        await tester.tap(find.byKey(const ValueKey('import_tab_text')));
        await safePumpAndSettle(tester);

        // Shaped like a hand-written list rather than the app's own export,
        // so the tolerance the recognizer promises is what gets exercised.
        await tester.enterText(
          find.byKey(const ValueKey('import_text_field')),
          '# Sharks\r\n- Carcharodon carcharias\r\n\r\n'
          '- Sphyrna   mokarran\r\n- Carcharodon carcharias\r\n',
        );
        await tester.tap(find.byKey(const ValueKey('import_text_button')));

        final nameField = find.byKey(const Key('create_deck_name_field'));
        await waitForFinder(tester, nameField);
        final speciesField = tester.widget<TextField>(
          find.byKey(const Key('create_deck_species_field')),
        );
        expect(
          speciesField.controller?.text,
          'Carcharodon carcharias\nSphyrna mokarran',
        );

        const deckName = 'Pasted Shark List';
        await tester.enterText(nameField, deckName);
        final submitButton = find.byKey(
          const ValueKey('create_deck_submit_button'),
        );
        await tester.scrollUntilVisible(
          submitButton,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(submitButton);
        await tester.pump(const Duration(milliseconds: 500));
        await dismissDownloadDialog(tester);

        await waitForFinder(tester, find.text(deckName));
        final decksService = Provider.of<DecksService>(
          tester.element(find.byType(MaterialApp)),
          listen: false,
        );
        final deck = (await decksService.getAllDecks()).singleWhere(
          (d) => d.stored.name == deckName,
        );
        final species = await decksService.getSpeciesByDeckId(deck.stored.id!);
        expect(
          species.map((s) => s.getBinomialName()),
          unorderedEquals(['Carcharodon carcharias', 'Sphyrna mokarran']),
        );
      },
      timeout: integrationTestTimeout,
    );
  });
}
