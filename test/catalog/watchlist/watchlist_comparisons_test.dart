import 'package:discere/catalog/comparison/comparison_page.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/watchlist/watchlist_tab.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comparison/comparison_test_app.dart';
import 'watchlist_tab_harness.dart';

Future<List<SpeciesWithLocalImages>> _resolve(Set<String> ids) async => [
  for (final id in ids) watchlistItem(id, 'species$id'),
];

void main() {
  late ComparisonListService comparisons;

  Future<void> pumpTab(
    WidgetTester tester, {
    List<String> watchlist = const [],
    List<ComparisonList> lists = const [],
  }) async {
    SharedPreferences.setMockInitialValues({'watchlist': watchlist});
    final prefs = await SharedPreferences.getInstance();
    comparisons = await loadedComparisonListService(tester, lists);
    await tester.pumpWidget(
      comparisonTestApp(
        service: comparisons,
        providers: [
          ChangeNotifierProvider<WatchlistService>.value(
            value: WatchlistService(prefs),
          ),
          ChangeNotifierProvider<LanguageService>.value(
            value: LanguageService(prefs),
          ),
        ],
        home: Scaffold(
          body: WatchlistTab(
            resolveFromCache: _resolve,
            resolveWithDownload: _resolve,
            buildSpeciesDetailPage: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switches between the watchlist\'s species and the comparison '
      'lists, which open a comparison', (tester) async {
    await pumpTab(
      tester,
      watchlist: ['sp1'],
      lists: const [
        ComparisonList(id: 'l1', name: 'Rays', speciesIds: ['sp1', 'sp2']),
      ],
    );
    expect(find.text('Genus speciessp1'), findsWidgets);
    expect(find.text('Rays'), findsNothing);

    await tester.tap(find.byKey(const Key('watchlist_view_comparisons')));
    await tester.pumpAndSettle();
    expect(find.text('Genus speciessp1'), findsNothing);
    expect(find.text('Rays'), findsOneWidget);
    expect(find.text('2 species'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('comparison_lists_item_l1')));
    await tester.pumpAndSettle();
    expect(find.byType(ComparisonPage), findsOneWidget);
  });

  testWidgets('without comparison lists, says how to make one', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byKey(const Key('watchlist_view_comparisons')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No comparisons yet.'), findsOneWidget);
  });

  testWidgets('species selected with a long press go into a new comparison, '
      'and the selection ends', (tester) async {
    await pumpTab(tester, watchlist: ['sp1', 'sp2', 'sp3']);

    await tester.longPress(find.text('Genus speciessp1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genus speciessp3').first);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('watchlist_selection_compare_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison_sheet_create_new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison_name_confirm_button')));
    await tester.pumpAndSettle();

    final created = comparisons.lists!.single;
    expect(created.speciesIds, ['sp1', 'sp3']);
    expect(created.name, 'Genus speciessp1, Genus speciessp3');
    expect(find.text('2 selected'), findsNothing);
  });
}
