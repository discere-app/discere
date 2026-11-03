import 'package:discere/catalog/comparison/comparison_page.dart';
import 'package:discere/catalog/comparison/comparison_species_section.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../watchlist/watchlist_tab_harness.dart';
import 'comparison_test_app.dart';

const _rays = ComparisonList(
  id: 'l1',
  name: 'Rays',
  speciesIds: ['sp1', 'sp2', 'sp3'],
);

Future<List<SpeciesWithLocalImages>> _resolve(Set<String> ids) async => [
  for (final id in ids) watchlistItem(id, 'species$id'),
];

void main() {
  late ComparisonListService service;

  /// Opens the page for [_rays] on a portrait screen unless [landscape].
  Future<void> pumpComparisonPage(
    WidgetTester tester, {
    bool landscape = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = landscape
        ? const Size(1200, 700)
        : const Size(500, 2400);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = await loadedComparisonListService(tester, const [_rays]);
    await tester.pumpWidget(
      comparisonTestApp(
        service: service,
        providers: [
          ChangeNotifierProvider<LanguageService>.value(
            value: LanguageService(prefs),
          ),
        ],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ComparisonPage(
                  list: _rays,
                  resolveFromCache: _resolve,
                  resolveWithDownload: _resolve,
                  buildSpeciesDetailPage: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The section of a species; its name shows twice in it, as the primary
  /// name and as the scientific one, since the test species have no common
  /// names.
  Finder section(String scientificName) => find
      .ancestor(
        of: find.text('Genus $scientificName'),
        matching: find.byType(ComparisonSpeciesSection),
      )
      .first;

  testWidgets('shows one section per species, one below the other in the '
      'list\'s order', (tester) async {
    await pumpComparisonPage(tester);

    expect(find.text('Rays'), findsOneWidget);
    expect(find.byType(ComparisonSpeciesSection), findsNWidgets(3));
    final first = tester.getTopLeft(section('speciessp1'));
    final second = tester.getTopLeft(section('speciessp2'));
    final third = tester.getTopLeft(section('speciessp3'));
    expect(first.dx, second.dx);
    expect(first.dy, lessThan(second.dy));
    expect(second.dy, lessThan(third.dy));
  });

  testWidgets('puts two species side by side in landscape', (tester) async {
    await pumpComparisonPage(tester, landscape: true);

    final first = tester.getTopLeft(section('speciessp1'));
    final second = tester.getTopLeft(section('speciessp2'));
    final third = tester.getTopLeft(section('speciessp3'));
    expect(first.dy, second.dy);
    expect(first.dx, lessThan(second.dx));
    expect(third.dx, first.dx);
    expect(third.dy, greaterThan(first.dy));
  });

  testWidgets(
    'swiping a species away removes it from the list and the screen',
    (tester) async {
      await pumpComparisonPage(tester);

      await tester.fling(section('speciessp2'), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();

      expect(service.listById('l1')!.speciesIds, ['sp1', 'sp3']);
      expect(find.byType(ComparisonSpeciesSection), findsNWidgets(2));
      expect(find.text('Genus speciessp2'), findsNothing);
    },
  );

  testWidgets('deleting the list after confirming closes the page', (
    tester,
  ) async {
    await pumpComparisonPage(tester);

    await tester.tap(find.byKey(const Key('comparison_page_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison_page_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison_delete_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ComparisonPage), findsNothing);
    expect(service.lists, isEmpty);
  });
}
