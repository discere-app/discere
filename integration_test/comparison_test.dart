import 'package:discere/catalog/comparison/comparison_page.dart';
import 'package:discere/catalog/comparison/comparison_species_section.dart';
import 'package:discere/catalog/search/search_result_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  group('comparison', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'a species added to a new comparison from its detail page shows in '
      'that comparison, opened from the confirmation and from the watchlist '
      'tab',
      (WidgetTester tester) async {
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
        );

        // 1. Find the species and open its detail page.
        await tester.tap(find.byIcon(Icons.search));
        await safePumpAndSettle(tester);
        await tester.enterText(
          find.byType(TextField),
          'Carcharodon carcharias',
        );
        final result = find.descendant(
          of: find.byType(SearchResultListItem),
          matching: find.textContaining('Carcharodon'),
        );
        await waitForFinder(
          tester,
          result,
          description: 'a search result for Carcharodon carcharias',
        );
        await tester.tap(result.first);
        final compareButton = find.byKey(
          const Key('species_detail_compare_button'),
        );
        await waitForFinder(
          tester,
          compareButton,
          description: 'the species detail page with its compare action',
        );

        // 2. Add it to a new comparison, under the name suggested for it.
        await tester.tap(compareButton);
        final createNew = find.byKey(const Key('comparison_sheet_create_new'));
        await waitForFinder(tester, createNew);
        await tester.tap(createNew);
        final nameField = find.byKey(const Key('comparison_name_field'));
        await waitForFinder(tester, nameField);
        expect(
          tester.widget<TextField>(nameField).controller!.text,
          'Carcharodon carcharias',
        );
        await tester.tap(
          find.byKey(const Key('comparison_name_confirm_button')),
        );
        await waitForAbsence(
          tester,
          createNew,
          description: 'the comparison sheet to close once the list exists',
        );

        // 3. The confirmation opens the new comparison, with the species in
        // it; back from there onto the detail page.
        final show = find.byKey(const Key('comparison_added_show_action'));
        await waitForFinder(tester, show, description: 'the "Show" action');
        await tester.tap(show);
        final speciesInComparison = find.descendant(
          of: find.byType(ComparisonSpeciesSection),
          matching: find.text('Carcharodon carcharias'),
        );
        await waitForFinder(
          tester,
          speciesInComparison,
          description: 'the comparison opened from the confirmation',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(ComparisonPage),
            matching: find.byType(BackButton),
          ),
        );
        await safePumpAndSettle(tester);

        // 4. Back to the main screen: off the detail page, then out of the
        // search.
        await tester.tap(
          find.descendant(
            of: find.ancestor(of: compareButton, matching: find.byType(AppBar)),
            matching: find.byType(BackButton),
          ),
        );
        await safePumpAndSettle(tester);
        await tester.tap(find.byIcon(Icons.arrow_back));
        final watchlistTab = find.byKey(const ValueKey('nav_watchlist'));
        await waitForFinder(tester, watchlistTab);

        // 5. The same comparison, opened from the watchlist tab.
        await tester.tap(watchlistTab);
        await safePumpAndSettle(tester);
        await tester.tap(find.byKey(const Key('watchlist_view_comparisons')));
        final comparison = find.text('Carcharodon carcharias');
        await waitForFinder(
          tester,
          comparison,
          description: 'the new comparison in the list of comparisons',
        );
        await tester.tap(comparison);

        await waitForFinder(
          tester,
          speciesInComparison,
          description: 'the comparison showing the species',
        );
      },
      timeout: integrationTestTimeout,
    );
  });
}
