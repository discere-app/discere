import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/search_results_grouped_list.dart';
import 'package:discere/catalog/search/taxonomy_search_result_card.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // The thumbnail cache is static and shared across every test in this
  // shard, so a thumbnail resolved here must not leak into the next test.
  setUp(SearchResultThumbnail.resetCacheForTesting);

  final octopus = _result(
    id: 'species-1',
    name: 'Enteroctopus dofleini',
    commonName: 'Giant Pacific octopus',
    type: SearchEntityType.species,
  );
  final squid = _result(
    id: 'species-2',
    name: 'Loligo vulgaris',
    commonName: 'European squid',
    type: SearchEntityType.species,
  );
  final genus = _result(
    id: 'genus-1',
    name: 'Enteroctopus',
    commonName: 'Giant octopuses',
    type: SearchEntityType.genus,
  );

  testWidgets('labels each rank once more than one is on screen', (
    tester,
  ) async {
    await tester.pumpWidget(_buildList([octopus, genus]));
    await tester.pumpAndSettle();

    expect(find.text('Species'), findsOneWidget);
    expect(find.text('Genera'), findsOneWidget);
  });

  testWidgets('drops the labels when every result shares one rank', (
    tester,
  ) async {
    await tester.pumpWidget(_buildList([octopus, squid]));
    await tester.pumpAndSettle();

    expect(find.text('Species'), findsNothing);
    expect(find.text('Giant Pacific octopus'), findsOneWidget);
    expect(find.text('European squid'), findsOneWidget);
  });

  testWidgets('renders a species row and a taxonomy card per rank', (
    tester,
  ) async {
    await tester.pumpWidget(_buildList([octopus, genus]));
    await tester.pumpAndSettle();

    expect(find.byType(SpeciesListItem), findsOneWidget);
    expect(find.byType(TaxonomySearchResultCard), findsOneWidget);
  });

  testWidgets('reports which result was tapped', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      _buildList([octopus, genus], onResultTap: (r) => tapped.add(r.id)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Giant octopuses'));
    await tester.tap(find.text('Giant Pacific octopus'));

    expect(tapped, ['genus-1', 'species-1']);
  });

  testWidgets('looks a species picture up by its id and a genus picture by '
      'its name key, each through its own resolver', (tester) async {
    final speciesKeys = <String>[];
    final higherTaxonKeys = <String>[];
    await tester.pumpWidget(
      _buildList(
        [octopus, genus],
        resolveThumbnailUrl: (key) async {
          speciesKeys.add(key);
          return null;
        },
        resolveHigherTaxonThumbnailUrl: (key) async {
          higherTaxonKeys.add(key);
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(speciesKeys, ['species-1']);
    expect(higherTaxonKeys, ['genus:enteroctopus']);
  });
}

SearchResult _result({
  required String id,
  required String name,
  required String commonName,
  required SearchEntityType type,
}) {
  return SearchResult(
    id: id,
    name: name,
    commonNames: {
      Language.en: [commonName],
    },
    type: type,
  );
}

Widget _buildList(
  List<SearchResult> results, {
  void Function(SearchResult result)? onResultTap,
  Future<String?> Function(String speciesId)? resolveThumbnailUrl,
  Future<String?> Function(String entityKey)? resolveHigherTaxonThumbnailUrl,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SearchResultsGroupedList(
        results: results,
        selectedLanguage: Language.en,
        resolveThumbnailUrl: resolveThumbnailUrl ?? (_) async => null,
        resolveHigherTaxonThumbnailUrl:
            resolveHigherTaxonThumbnailUrl ?? (_) async => null,
        onResultTap: onResultTap ?? (_) {},
      ),
    ),
  );
}
