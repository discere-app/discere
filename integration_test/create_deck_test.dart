import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

void main() {
  initializeIntegrationTest();


  group('Create Deck Page', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'can navigate to Create Deck and see Cover Image options',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(tester, notificationService: mockNotificationService);

        // 1. Open FAB
        final fab = find.byKey(const ValueKey('main_fab'));
        await tester.tap(fab);
        await safePumpAndSettle(tester);

        // 2. Tap Create Deck
        final createButton = find.byIcon(Icons.create_new_folder_outlined);
        await tester.tap(createButton);
        await safePumpAndSettle(tester);

        // 3. Verify labels on Create Deck Page
        expect(find.text('Create New Deck'), findsOneWidget);
        expect(find.text('Cover Image'), findsOneWidget);

        // 4. Verify the image picker's gallery button
        final galleryButton = find.byIcon(Icons.photo_library_outlined);
        await tester.dragUntilVisible(
          galleryButton,
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await safePumpAndSettle(tester);
        expect(galleryButton, findsWidgets);
      },
      timeout: integrationTestTimeout,
    );
    testWidgets(
      'the species field shows which names are found before creating',
      (tester) async {
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
        );

        await tester.tap(find.byKey(const ValueKey('main_fab')));
        await safePumpAndSettle(tester);
        await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
        await safePumpAndSettle(tester);

        const deckName = 'Checked Species Deck';
        await tester.enterText(
          find.byKey(const Key('create_deck_name_field')),
          deckName,
        );
        final speciesField = find.byKey(const Key('create_deck_species_field'));
        await tester.scrollUntilVisible(
          speciesField,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          speciesField,
          'Carcharodon carcharias\nUnknownus fishus',
        );

        // Shown once typing pauses and the catalog has answered.
        final found = find.byKey(const Key('create_deck_species_found'));
        final notFoundLocally = find.byKey(
          const Key('create_deck_species_not_found_locally'),
        );
        await waitForFinder(tester, found);
        await waitForFinder(tester, notFoundLocally);
        expect(
          find.descendant(
            of: notFoundLocally,
            matching: find.textContaining('Unknownus fishus'),
          ),
          findsOneWidget,
        );

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
        expect(species.map((s) => s.getBinomialName()), [
          'Carcharodon carcharias',
        ]);
      },
      timeout: integrationTestTimeout,
    );
  });
}
