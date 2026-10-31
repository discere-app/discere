import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

const _deckName = 'Reef Levels';

/// A shared deck with two subdecks, as the text import receives it.
const _deckJson =
    '''
{
  "name": "$_deckName",
  "description": "",
  "speciesNames": ["Amphiprion ocellaris", "Carcharodon carcharias",
                   "Rhincodon typus"],
  "subdecks": [
    {"id": "reef", "name": "Reef", "speciesNames": ["Amphiprion ocellaris"]},
    {"id": "sharks", "name": "Sharks",
     "speciesNames": ["Carcharodon carcharias", "Rhincodon typus"]}
  ]
}
''';

Future<void> _importDeck(WidgetTester tester) async {
  // Import the deck through the text tab.
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
  await tester.enterText(
    find.byKey(const ValueKey('import_text_field')),
    _deckJson,
  );
  await tester.tap(find.byKey(const ValueKey('import_text_button')));
  await waitForFinder(
    tester,
    find.byKey(const Key('create_deck_name_field')),
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
  await waitForFinder(tester, find.text(_deckName));
}

/// Opens the deck's review session, activating the deck when it asks to.
Future<void> _openSession(WidgetTester tester) async {
  await openDeck(tester, _deckName);
  final activation = find.byKey(const Key('activation_dialog_title'));
  if (activation.evaluate().isNotEmpty) {
    await tester.tap(
      find.byKey(const Key('activation_dialog_yes_button')),
    );
    await waitForAbsence(
      tester,
      activation,
      description: 'the activation dialog to close',
    );
  }
}

void main() {
  initializeIntegrationTest();

  group('subdecks', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'a switched-off subdeck keeps its species out of the review session',
      (tester) async {
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
        );

        await _importDeck(tester);

        // Switch the sharks off and save.
        await openEditDeck(tester);
        final sharksSwitch = find.byKey(
          const Key('edit_deck_subdeck_switch_sharks'),
          skipOffstage: false,
        );
        await waitForFinder(
          tester,
          sharksSwitch,
          description: 'the subdeck switches',
        );
        await tester.ensureVisible(sharksSwitch);
        await safePumpAndSettle(tester);
        await tester.tap(sharksSwitch);
        await safePumpAndSettle(tester);
        await tester.tap(find.byKey(const Key('edit_deck_save_button')));
        await safePumpAndSettle(tester);
        await waitForAbsence(
          tester,
          find.byKey(const Key('edit_deck_save_button')),
          description: 'Edit Deck to close after saving',
        );

        // The sharks stay in the deck, with their progress — they are only
        // no cards.
        final decksService = Provider.of<DecksService>(
          tester.element(find.byType(MaterialApp)),
          listen: false,
        );
        final deck = (await decksService.getAllDecks()).singleWhere(
          (d) => d.stored.name == _deckName,
        );
        final species = await decksService.getSpeciesByDeckId(deck.stored.id!);
        expect(species, hasLength(3));

        // The session holds the reef species alone.
        await _openSession(tester);
        await waitForFinder(
          tester,
          find.byIcon(Icons.thumb_up_rounded),
          description: 'the first card',
        );
        final card = tester.widget<FlashcardWidget>(
          find.byType(FlashcardWidget),
        );
        expect(
          card.speciesWithLocalImage.species.getBinomialName(),
          'Amphiprion ocellaris',
        );

        await tester.tap(find.byIcon(Icons.thumb_up_rounded));
        await safePumpAndSettle(tester);
        await waitForFinder(
          tester,
          find.byKey(const Key('no_more_cards_dialog_title')),
          description: 'the session to end after its one card',
        );
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'species assigned to a new subdeck leave the session with its switch',
      (tester) async {
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
        );
        await _importDeck(tester);

        await openEditDeck(tester);
        final addButton = find.byKey(
          const Key('edit_deck_subdeck_add_button'),
          skipOffstage: false,
        );
        await waitForFinder(
          tester,
          addButton,
          description: 'the add-subdeck button',
        );
        await tester.ensureVisible(addButton);
        await safePumpAndSettle(tester);
        await tester.tap(addButton);
        await safePumpAndSettle(tester);
        await tester.enterText(
          find.byKey(const Key('edit_deck_subdeck_name_field')),
          'Giants',
        );
        await safePumpAndSettle(tester);
        await tester.tap(
          find.byKey(const Key('edit_deck_subdeck_name_confirm_button')),
        );
        await waitForFinder(
          tester,
          find.text('Giants'),
          description: 'the new subdeck',
        );

        // Its row is the last one: the menu, its assign entry, the whale shark.
        await tester.tap(find.byIcon(Icons.adaptive.more).last);
        await safePumpAndSettle(tester);
        await tester.tap(
          find.byKey(const Key('edit_deck_subdeck_menu_assign_species')),
        );
        await safePumpAndSettle(tester);
        const whaleShark = 'discere:species:1872';
        final whaleSharkTile = find.byKey(
          const Key('edit_deck_subdeck_species_tile_$whaleShark'),
        );
        await waitForFinder(
          tester,
          whaleSharkTile,
          description: 'the species checklist',
        );
        await tester.tap(whaleSharkTile);
        await safePumpAndSettle(tester);
        await tester.tap(
          find.byKey(const Key('edit_deck_subdeck_species_confirm_button')),
        );
        await safePumpAndSettle(tester);

        // Switch it off: its switch is the last one of the section.
        final giantsSwitch = find
            .ancestor(
              of: find.text('Giants'),
              matching: find.byType(SwitchListTile),
            )
            .first;
        await tester.ensureVisible(giantsSwitch);
        await safePumpAndSettle(tester);
        await tester.tap(giantsSwitch);
        await safePumpAndSettle(tester);
        await tester.tap(find.byKey(const Key('edit_deck_save_button')));
        await safePumpAndSettle(tester);
        await waitForAbsence(
          tester,
          find.byKey(const Key('edit_deck_save_button')),
          description: 'Edit Deck to close after saving',
        );

        // The session holds the two others, and never the whale shark.
        await _openSession(tester);
        final seen = <String>{};
        for (var card = 0; card < 2; card++) {
          await waitForFinder(
            tester,
            find.byIcon(Icons.thumb_up_rounded),
            description: 'card ${card + 1}',
          );
          seen.add(
            tester
                .widget<FlashcardWidget>(find.byType(FlashcardWidget))
                .speciesWithLocalImage
                .species
                .getBinomialName(),
          );
          await tester.tap(find.byIcon(Icons.thumb_up_rounded));
          await safePumpAndSettle(tester);
        }
        expect(seen, {'Amphiprion ocellaris', 'Carcharodon carcharias'});
        await waitForFinder(
          tester,
          find.byKey(const Key('no_more_cards_dialog_title')),
          description: 'the session to end after its two cards',
        );
      },
      timeout: integrationTestTimeout,
    );
  });
}
