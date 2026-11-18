import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/higher_taxon_thumbnail_port.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/search_result_thumbnail_placeholder.dart';
import 'package:discere/catalog/search/species_thumbnail_port.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_children_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Records which keys each port was asked for, and has no picture to show.
class _RecordingThumbnails
    implements SpeciesThumbnailPort, HigherTaxonThumbnailPort {
  final requestedKeys = <String>[];

  @override
  Future<String?> thumbnailUrl(String key) async {
    requestedKeys.add(key);
    return null;
  }
}

SearchResult _child(
  String id,
  String name,
  SearchEntityType type, {
  bool isPlaceholder = false,
}) => SearchResult(
  id: id,
  name: name,
  commonNames: const {},
  type: type,
  isPlaceholder: isPlaceholder,
);

void main() {
  late _RecordingThumbnails speciesThumbnails;
  late _RecordingThumbnails higherTaxonThumbnails;

  // The thumbnail cache is static and shared across every test in this
  // shard, so a key resolved here must not leak into the next test.
  setUp(() {
    SearchResultThumbnail.resetCacheForTesting();
    speciesThumbnails = _RecordingThumbnails();
    higherTaxonThumbnails = _RecordingThumbnails();
  });
  tearDown(SearchResultThumbnail.resetCacheForTesting);

  Future<void> pumpChildren(
    WidgetTester tester,
    List<SearchResult> children,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SpeciesThumbnailPort>.value(value: speciesThumbnails),
          Provider<HigherTaxonThumbnailPort>.value(
            value: higherTaxonThumbnails,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaxonomyChildrenSection(
                future: Future.value(children),
                parentType: SearchEntityType.family,
                accent: Colors.teal,
                language: Language.en,
                speciesListItemPresenter: const SpeciesListItemPresenter(),
                onNavigate: (_) {},
                canNavigateToSpecies: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('looks a genus picture up by its name key, not its id', (
    tester,
  ) async {
    await pumpChildren(tester, [
      _child(
        'discere:fishbase_genus:10875',
        'Carcharodon',
        SearchEntityType.genus,
      ),
    ]);

    expect(higherTaxonThumbnails.requestedKeys, ['genus:carcharodon']);
    expect(speciesThumbnails.requestedKeys, isEmpty);
  });

  testWidgets('looks a species picture up by its id, through the species '
      'port alone', (tester) async {
    await pumpChildren(tester, [
      _child(
        'discere:species:1',
        'Carcharodon carcharias',
        SearchEntityType.species,
      ),
    ]);

    expect(speciesThumbnails.requestedKeys, ['discere:species:1']);
    expect(higherTaxonThumbnails.requestedKeys, isEmpty);
  });

  testWidgets('gives a rank placeholder row the placeholder picture without '
      'asking for one', (tester) async {
    await pumpChildren(tester, [
      _child(
        'discere:fishbase_genus:0',
        'Not assigned',
        SearchEntityType.genus,
        isPlaceholder: true,
      ),
    ]);

    expect(higherTaxonThumbnails.requestedKeys, isEmpty);
    expect(speciesThumbnails.requestedKeys, isEmpty);
    expect(find.byType(SearchResultThumbnailPlaceholder), findsOneWidget);
  });
}
