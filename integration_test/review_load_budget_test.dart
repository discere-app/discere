import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

/// Guards the load time of a review session (#229): opening a deck whose
/// cards are due must put the first card on screen in well under a second,
/// whatever the session's size.
///
/// The work a session genuinely needs for its first card is fixed — three
/// user-DB queries (deck config, stat backfill, due stats), one bundled
/// species load, one bundled photo-cache read, one documents-directory lookup
/// and a handful of `File.exists` calls, all over indexes. On a real mid-range
/// device with the full reference DB that is a ~500ms budget; the 1000ms here
/// doubles it for a CI emulator sharing its runner with other jobs. It is an
/// upper bound on a regression, not a performance measurement: the guard
/// against the actual defect — per-card instead of per-session work — is
/// `species_media_service_test.dart`, which counts the queries.
const _firstCardBudget = Duration(milliseconds: 1000);

/// 20 fixture species, each spelled as the fixture's own `species` row has it
/// and each resolving to exactly one entry, so the automatic first batch of 10
/// (see FlashcardReviewService.initializeNextBatch) leaves ten cards due when
/// the deck is reopened.
const _speciesNames = [
  'Amphiprion ocellaris',
  'Abramis brama',
  'Carcharodon carcharias',
  'Enteroctopus dofleini',
  'Natator depressa',
  'Oncorhynchus mykiss',
  'Phoxinus phoxinus',
  'Pterois miles',
  'Rhincodon typus',
  'Thymallus thymallus',
  'Chelonia mydas',
  'Galeocerdo cuvier',
  'Costoanachis cascabulloi',
  'Staurastrum limneticum',
  'Nicolea chilensis',
  'Trichopodus trichopterus',
  'Americhelidium shoemakeri',
  'Labracinus atrofasciatus',
  'Scabricola eximia',
  'Stercorarius pomarinus',
];

final _ratingButtons = find.byIcon(Icons.thumb_up_rounded);

void main() {
  initializeIntegrationTest();

  group('review load budget', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'puts the first card of a full batch on screen within the budget',
      (WidgetTester tester) async {
        final mockNotificationService = createMockNotificationService();

        const deckName = 'Load Budget Deck';
        await startApp(
          tester,
          notificationService: mockNotificationService,
          withTestDeck: true,
          deckName: deckName,
          species: _speciesNames.join('\n'),
        );

        // The first open activates the batch: a DB write plus a second session
        // load, which is startup work rather than the load being budgeted.
        await openDeck(tester, deckName);
        await waitForFinder(
          tester,
          _ratingButtons,
          description: 'the first card of the freshly activated batch',
        );
        await _dismissNoDataDialogIfPresent(tester);

        // Leaving without grading keeps all ten cards due for the reopen.
        await tester.pageBack();
        await waitForAbsence(
          tester,
          _ratingButtons,
          description: 'the review screen to be left behind',
        );

        final elapsed = await _measureTimeToFirstCard(tester, deckName);
        debugPrint('-- TEST: first card after ${elapsed.inMilliseconds}ms --');

        expect(
          elapsed,
          lessThan(_firstCardBudget),
          reason:
              'opening a deck with 10 cards due took ${elapsed.inMilliseconds}ms '
              'to show the first card, over the ${_firstCardBudget.inMilliseconds}ms budget',
        );
      },
      timeout: integrationTestTimeout,
    );
  });
}

/// Taps the deck and returns how long the first card's controls took to
/// render. Scrolling and waiting for the deck list happen before the clock
/// starts, so only the session load is measured.
Future<Duration> _measureTimeToFirstCard(
  WidgetTester tester,
  String deckName,
) async {
  final deckList = find.byKey(const Key('home_deck_list'));
  await waitForFinder(
    tester,
    deckList,
    description: 'the deck list to be loaded',
  );
  final deckFinder = find.text(deckName);
  await tester.scrollUntilVisible(
    deckFinder,
    500,
    scrollable: find.descendant(
      of: deckList,
      matching: find.byType(Scrollable),
    ),
  );

  final stopwatch = Stopwatch()..start();
  await tester.tap(deckFinder.last);
  // Pumped a frame at a time rather than in the default 200ms steps, so the
  // measurement isn't quantized to a fifth of the budget.
  await waitForCondition(
    tester,
    () => _ratingButtons.evaluate().isNotEmpty,
    description: 'the first card of the reopened deck to render',
    step: const Duration(milliseconds: 16),
  );
  return stopwatch.elapsed;
}

/// Closes the "nothing downloaded for this deck yet" offer if the deck page
/// raised it, so the following back navigation pops the page and not a dialog.
Future<void> _dismissNoDataDialogIfPresent(WidgetTester tester) async {
  final laterButton = find.byKey(const Key('no_data_downloaded_later_button'));
  if (laterButton.evaluate().isEmpty) return;
  await tester.tap(laterButton);
  await waitForAbsence(
    tester,
    find.byKey(const Key('no_data_downloaded_dialog')),
    description: 'the no-data-downloaded dialog to close',
  );
}
