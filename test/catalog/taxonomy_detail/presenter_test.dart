import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_presenter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TaxonomyDetailPresenter presenter;
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    presenter = const TaxonomyDetailPresenter();
  });

  test(
    'falls back to english common names when selected language is empty',
    () {
      final detail = TaxonomyDetail(
        result: SearchResult(
          id: 'family:lamnidae',
          name: 'Lamnidae',
          commonNames: const {
            Language.de: [],
            Language.en: ['Mackerel sharks', 'Mackerel sharks', 'White sharks'],
          },
          type: SearchEntityType.family,
        ),
        commonNames: const {
          Language.de: [],
          Language.en: ['Mackerel sharks', 'Mackerel sharks', 'White sharks'],
        },
        classification: const [],
        metrics: const [],
        isReferenceBacked: true,
      );

      final viewData = presenter.present(detail, Language.de, en);

      expect(viewData.pageTitle, 'Family');
      expect(viewData.primaryTitle, 'Mackerel sharks');
      expect(viewData.commonNames, ['Mackerel sharks', 'White sharks']);
    },
  );

  test(
    'maps metrics, classification labels, and attributes to display text',
    () {
      final detail = TaxonomyDetail(
        result: SearchResult(
          id: 'genus:carcharodon',
          name: 'Carcharodon',
          commonNames: const {},
          type: SearchEntityType.genus,
        ),
        commonNames: const {},
        classification: const [
          TaxonomyClassificationEntry(
            label: TaxonomyRankLabel.family,
            scientificName: 'Lamnidae',
            commonName: 'Mackerel sharks',
          ),
        ],
        metrics: const [
          TaxonomyMetric(type: TaxonomyMetricType.species, count: 2),
        ],
        attributes: const [
          TaxonomyAttribute(key: 'body_shape', value: 'fusiform / normal'),
        ],
        isReferenceBacked: false,
      );

      final viewData = presenter.present(detail, Language.en, en);

      expect(viewData.entityLabel, 'Genus');
      expect(viewData.metrics.single.label, en.searchDetailContainedSpecies);
      expect(viewData.classificationRows.single.label, 'Family');
      expect(viewData.attributes.single.label, 'Body Shape');
      expect(viewData.emptyClassificationLabel, en.searchDetailReferenceHint);
    },
  );

  test(
    'classification entries propagate id and entityType for each navigable rank',
    () {
      final detail = TaxonomyDetail(
        result: SearchResult(
          id: 'genus-1',
          name: 'Carcharodon',
          commonNames: const {},
          type: SearchEntityType.genus,
        ),
        commonNames: const {},
        classification: const [
          TaxonomyClassificationEntry(
            label: TaxonomyRankLabel.family,
            id: 'family-1',
            scientificName: 'Lamnidae',
          ),
          TaxonomyClassificationEntry(
            label: TaxonomyRankLabel.order,
            id: 'order-1',
            scientificName: 'Lamniformes',
          ),
          TaxonomyClassificationEntry(
            label: TaxonomyRankLabel.classType,
            id: 'class-1',
            scientificName: 'Chondrichthyes',
          ),
          TaxonomyClassificationEntry(
            label: TaxonomyRankLabel.superClass,
            scientificName: 'Vertebrata',
          ),
        ],
        metrics: const [],
        isReferenceBacked: true,
      );

      final viewData = presenter.present(detail, Language.en, en);
      final rows = viewData.classificationRows;

      expect(rows[0].id, 'family-1');
      expect(rows[0].entityType, SearchEntityType.family);
      expect(rows[1].id, 'order-1');
      expect(rows[1].entityType, SearchEntityType.order);
      expect(rows[2].id, 'class-1');
      expect(rows[2].entityType, SearchEntityType.classType);
      expect(rows[3].id, isNull);
      expect(rows[3].entityType, isNull);
    },
  );

  test(
    'classification entry without id has null id but retains entityType from label',
    () {
      final detail = TaxonomyDetail(
        result: SearchResult(
          id: 'genus-1',
          name: 'Carcharodon',
          commonNames: const {},
          type: SearchEntityType.genus,
        ),
        commonNames: const {},
        classification: const [
          TaxonomyClassificationEntry(
            label: TaxonomyRankLabel.family,
            scientificName: 'Lamnidae',
          ),
        ],
        metrics: const [],
        isReferenceBacked: false,
      );

      final viewData = presenter.present(detail, Language.en, en);

      // id is null → widget treats the row as non-navigable (id != null check)
      expect(viewData.classificationRows.single.id, isNull);
      // entityType is still derived from the label
      expect(
        viewData.classificationRows.single.entityType,
        SearchEntityType.family,
      );
    },
  );

  test(
    'pageTitleFor returns the entity-type label without needing a loaded '
    'TaxonomyDetail',
    () {
      expect(
        presenter.pageTitleFor(SearchEntityType.genus, en),
        en.classificationGenus,
      );
      expect(
        presenter.pageTitleFor(SearchEntityType.family, en),
        en.classificationFamily,
      );
      expect(
        presenter.pageTitleFor(SearchEntityType.species, en),
        en.classificationSpecies,
      );
    },
  );
}
