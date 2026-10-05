import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

/// Smoke guard for the load time of a review session (#229): opening a deck
/// whose cards are due must put the first card on screen promptly.
///
/// Deliberately a loose bound, because this fixture cannot carry a tight one.
/// Measured back to back on one API-33 emulator boot, the median of three opens
/// is the same with per-card and with bundled resolution (780ms against 781ms):
/// ten cards against a 1.4MB database that is entirely in the page cache cost
/// almost nothing either way. What this test therefore guards is that the
/// review screen still loads, and does not become grossly slow — a
/// reintroduced network call on the load path, say.
///
/// It is NOT what guards the defect behind #229, per-card instead of
/// per-session work. That is `species_media_service_test.dart`, which counts
/// the database round trips and requires the same number for one species as for
/// 25. The defect shows up in time only at a data size this fixture does not
/// have: against the production reference database, loading 200 species takes
/// 277ms one by one and 23ms bundled.
///
/// Two bounds, because the machines differ more than the code could. On a
/// local emulator the median of three opens is about 0.7s, so 2s still
/// catches a load that has become grossly slow. On the GitHub-hosted API-30
/// emulator the same code ranges from about 1.4s to 2.6s; a bound inside that
/// spread fails on runner load rather than on the app, so CI ([runsOnCi])
/// gets 5s.
const _firstCardBudget = Duration(milliseconds: runsOnCi ? 5000 : 2000);

/// How many opens the median is taken over. A single sample on an emulator
/// swings by a factor of three — the window starts at the tap and so contains
/// the route transition, frame scheduling and the enrichment queue's own work —
/// which would make even a loose bound flaky.
const _measuredOpens = 3;

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
        await _leaveDeck(tester);

        // Nothing is graded in between, so every open finds the same ten cards
        // due and measures the same work.
        final samples = <Duration>[];
        for (var i = 0; i < _measuredOpens; i++) {
          samples.add(await _measureTimeToFirstCard(tester, deckName));
          await _leaveDeck(tester);
        }
        samples.sort();
        final median = samples[_measuredOpens ~/ 2];
        debugPrint(
          '-- TEST: first card after '
          '${samples.map((s) => s.inMilliseconds).join('/')}ms, '
          'median ${median.inMilliseconds}ms --',
        );

        expect(
          median,
          lessThan(_firstCardBudget),
          reason:
              'opening a deck with 10 cards due took a median of '
              '${median.inMilliseconds}ms over $_measuredOpens opens '
              '(${samples.map((s) => s.inMilliseconds).join('/')}ms) to show '
              'the first card, over the '
              '${_firstCardBudget.inMilliseconds}ms budget',
        );
      },
      timeout: integrationTestTimeout,
    );
  });
}

/// Taps the deck and returns how long the first card's controls took to appear
/// — what a user waits through, which includes the route transition on top of
/// the session load. Scrolling and waiting for the deck list happen before the
/// clock starts, so at least the way to the deck is not counted.
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
  // measurement isn't quantized to 200ms.
  await waitForCondition(
    tester,
    () => _ratingButtons.evaluate().isNotEmpty,
    description: 'the first card of the reopened deck to render',
    step: const Duration(milliseconds: 16),
  );
  return stopwatch.elapsed;
}

/// Leaves the review screen the way a user would, dismissing the "nothing
/// downloaded for this deck yet" offer first when the deck page raised it — so
/// the back navigation pops the page and not a dialog.
Future<void> _leaveDeck(WidgetTester tester) async {
  await _dismissNoDataDialogIfPresent(tester);
  await tester.pageBack();
  await waitForAbsence(
    tester,
    _ratingButtons,
    description: 'the review screen to be left behind',
  );
}

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
