import 'package:discere/catalog/search/search_online_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

/// What the iNaturalist v2 `/taxa` search answers when it knows the name.
///
/// Only the envelope and the keys `INatSearchApi.searchTaxa` actually reads
/// are here — a free-text search is a POST carrying the field selection, and
/// the reply is `{total_results, page, per_page, results: [...]}` with one
/// taxon per entry.
const _pteroisMilesTaxaResponse = '''
{
  "total_results": 1,
  "page": 1,
  "per_page": 20,
  "results": [
    {
      "id": 118920,
      "rank": "species",
      "name": "Pterois miles",
      "preferred_common_name": "Devil Firefish",
      "matched_term": "Indian lionfish",
      "iconic_taxon_name": "Actinopterygii",
      "default_photo": {
        "id": 4411,
        "url": "https://inaturalist-open-data.s3.amazonaws.com/photos/4411/square.jpg",
        "medium_url": "https://inaturalist-open-data.s3.amazonaws.com/photos/4411/medium.jpg",
        "license_code": "cc-by-nc"
      }
    }
  ]
}
''';

const _emptyTaxaResponse = '''
{"total_results": 0, "page": 1, "per_page": 20, "results": []}
''';

/// The query: an English name for *Pterois miles* that the reference fixture
/// does not carry under any of its names (it lists "Devil firefish" and
/// "Soldier lionfish"), so every local branch — species FTS, common-name
/// FTS, the `LIKE` fallback — comes up empty, while the species itself is in
/// the fixture and can be matched back by its scientific name.
const _query = 'Indian lionfish';

void main() {
  initializeIntegrationTest();

  group('online search', () {
    setUp(() async {
      await resetTestState();
    });

    testWidgets(
      'a name only iNaturalist knows resolves to a reference species',
      (tester) async {
        // iNaturalist is asked twice for a query with no local hits: the full
        // search already consults it on its own, and the "search online"
        // action asks again. The stub only knows the species once
        // [iNatKnowsSpecies] is set, which happens immediately before the
        // tap — so a hit on screen afterwards can only have come from the
        // round that button started, no matter how many rounds ran before.
        var iNatKnowsSpecies = false;
        final taxaSearches = <Uri>[];
        final client = MockClient((request) async {
          final isFreeTextTaxonSearch =
              request.method == 'POST' && request.url.path == '/v2/taxa';
          if (!isFreeTextTaxonSearch) {
            // Thumbnail lookups, deck-update checks, images: nothing this
            // flow depends on. 404 rather than a 5xx, which would put the
            // host into a cooldown the next request has to wait out.
            return http.Response('{}', 404);
          }
          taxaSearches.add(request.url);
          if (!iNatKnowsSpecies) {
            return http.Response(_emptyTaxaResponse, 200);
          }
          // Long enough for the running state to be observable on screen.
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response(_pteroisMilesTaxaResponse, 200);
        });

        await startApp(
          tester,
          notificationService: createMockNotificationService(),
          httpClient: client,
        );

        await tester.tap(find.byIcon(Icons.search));
        await safePumpAndSettle(tester);
        await tester.enterText(find.byType(TextField), _query);
        await safePumpAndSettle(tester);

        // The action only appears once the local search has settled without
        // an answer, so its presence is the "nothing found locally" step.
        final onlineButton = find.byType(SearchOnlineButton);
        await waitForFinder(
          tester,
          onlineButton,
          description: 'the online-search action to be offered',
        );
        expect(find.textContaining('Pterois'), findsNothing);
        expect(
          taxaSearches.any((uri) => uri.queryParameters['q'] == _query),
          isTrue,
          reason: 'the query should reach iNaturalist as the user typed it',
        );

        iNatKnowsSpecies = true;
        await tester.tap(onlineButton);
        await tester.pump();

        await waitForCondition(
          tester,
          () =>
              onlineButton.evaluate().isNotEmpty &&
              tester.widget<SearchOnlineButton>(onlineButton).isSearchingOnline,
          description: 'the online round to report itself as running',
        );

        await waitForFinder(
          tester,
          find.text('Pterois miles'),
          description: 'the species matched back from the online hit',
        );
        // Round over: the action is gone rather than inviting a repeat of a
        // request that has already been answered.
        expect(onlineButton, findsNothing);
      },
      timeout: integrationTestTimeout,
    );
  });
}
