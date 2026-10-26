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
  });
}
