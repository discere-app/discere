import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/comparison/comparison_page.dart';
import 'package:discere/catalog/comparison/comparison_species_section.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/species.dart';
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

/// A species showing every fact a comparison compares, with long values, so
/// that they wrap onto a second line on a phone.
SpeciesWithLocalImages _withFacts(String id) {
  final item = watchlistItem(id, 'species$id');
  final species = item.species;
  return SpeciesWithLocalImages(
    Species(
      species.id,
      species.externalId,
      species.externalSource,
      species.scientificName,
      const {},
      species.classification,
      species.pictures,
      maxLengthCm: 1234.5,
      depthMinM: 1000,
      depthMaxM: 3500,
      habitatTag: HabitatTag.openOceanMesopelagic,
    ),
    item.localPictures,
  );
}

void main() {
  late ComparisonListService service;

  /// Opens the page for [list] on a tall portrait screen, a landscape one if
  /// [landscape], or one of [size].
  Future<void> pumpComparisonPage(
    WidgetTester tester, {
    bool landscape = false,
    Size? size,
    ComparisonList list = _rays,
    ResolveSpeciesWithImages resolve = _resolve,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        size ?? (landscape ? const Size(1200, 700) : const Size(500, 2400));
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = await loadedComparisonListService(tester, [list]);
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
                  list: list,
                  resolveFromCache: resolve,
                  resolveWithDownload: resolve,
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

  /// The species on screen, top to bottom.
  List<String> shownOrder(WidgetTester tester) {
    final sections = find.byType(ComparisonSpeciesSection).evaluate().toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
    return [
      for (final section in sections)
        (section.widget as ComparisonSpeciesSection).species.scientificName,
    ];
  }

  testWidgets('the remove button takes a species out; undo puts it back in '
      'its old place', (tester) async {
    await pumpComparisonPage(tester);

    await tester.tap(
      find.descendant(
        of: section('speciessp2'),
        matching: find.byKey(const Key('comparison_species_remove')),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.listById('l1')!.speciesIds, ['sp1', 'sp3']);
    expect(shownOrder(tester), ['Genus speciessp1', 'Genus speciessp3']);
    expect(find.text('Removed "Genus speciessp2"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('comparison_species_undo')));
    await tester.pumpAndSettle();

    expect(service.listById('l1')!.speciesIds, ['sp1', 'sp2', 'sp3']);
    expect(shownOrder(tester), [
      'Genus speciessp1',
      'Genus speciessp2',
      'Genus speciessp3',
    ]);
  });

  testWidgets('swiping across a species leaves it in the comparison', (
    tester,
  ) async {
    await pumpComparisonPage(tester);

    await tester.fling(section('speciessp2'), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();

    expect(service.listById('l1')!.speciesIds, ['sp1', 'sp2', 'sp3']);
    expect(find.byType(ComparisonSpeciesSection), findsNWidgets(3));
  });

  testWidgets('on a phone in portrait, two species with their facts fit the '
      'screen whole', (tester) async {
    await pumpComparisonPage(
      tester,
      size: const Size(390, 844),
      list: const ComparisonList(
        id: 'l1',
        name: 'Rays',
        speciesIds: ['sp1', 'sp2'],
      ),
      resolve: (ids) async => [for (final id in ids) _withFacts(id)],
    );

    final viewport = tester.getRect(find.byType(ListView));
    final sections = find.byType(ComparisonSpeciesSection);
    expect(sections, findsNWidgets(2));
    for (final section in sections.evaluate()) {
      final rect = tester.getRect(find.byWidget(section.widget));
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    }
  });

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
