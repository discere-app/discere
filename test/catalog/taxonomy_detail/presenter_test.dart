import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_presenter.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
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
      expect(viewData.isEnglishFallback, isTrue);
    },
  );

  test('does not flag an English fallback when the selected language '
      'already has a common name', () {
    final detail = TaxonomyDetail(
      result: SearchResult(
        id: 'family:lamnidae',
        name: 'Lamnidae',
        commonNames: const {},
        type: SearchEntityType.family,
      ),
      commonNames: const {
        Language.de: ['Makrelenhaie'],
        Language.en: ['Mackerel sharks'],
      },
      classification: const [],
      metrics: const [],
      isReferenceBacked: true,
    );

    final viewData = presenter.present(detail, Language.de, en);

    expect(viewData.primaryTitle, 'Makrelenhaie');
    expect(viewData.isEnglishFallback, isFalse);
  });

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
            commonNames: {
              Language.en: ['Mackerel sharks'],
            },
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
      expect(viewData.emptyClassificationLabel, en.commonNoData);
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

  group('a classification row\'s common name', () {
    TaxonomyDetail detailWithFamilyNames(
      Map<Language, List<String>> familyNames,
    ) => TaxonomyDetail(
      result: SearchResult(
        id: 'genus-1',
        name: 'Carcharodon',
        commonNames: const {},
        type: SearchEntityType.genus,
      ),
      commonNames: const {},
      classification: [
        TaxonomyClassificationEntry(
          label: TaxonomyRankLabel.family,
          id: 'family-1',
          scientificName: 'Lamnidae',
          commonNames: familyNames,
        ),
      ],
      metrics: const [],
      isReferenceBacked: true,
    );

    String? familyNameIn(
      Language language,
      Map<Language, List<String>> familyNames,
    ) => presenter
        .present(detailWithFamilyNames(familyNames), language, en)
        .classificationRows
        .single
        .commonName;

    test('is the one in the requested language', () {
      const names = {
        Language.en: ['Mackerel sharks'],
        Language.de: ['Makrelenhaie'],
        Language.fr: ['Requins-taupes'],
      };

      expect(familyNameIn(Language.de, names), 'Makrelenhaie');
      expect(familyNameIn(Language.fr, names), 'Requins-taupes');
      expect(familyNameIn(Language.en, names), 'Mackerel sharks');
    });

    test('falls back to English when the requested language has none', () {
      const names = {
        Language.en: ['Mackerel sharks'],
        Language.de: ['Makrelenhaie'],
        Language.es: <String>[],
      };

      expect(familyNameIn(Language.es, names), 'Mackerel sharks');
      expect(familyNameIn(Language.fr, names), 'Mackerel sharks');
    });

    test('is absent when neither the requested language nor English has '
        'one', () {
      expect(
        familyNameIn(Language.es, const {
          Language.de: ['Makrelenhaie'],
        }),
        isNull,
      );
      expect(familyNameIn(Language.en, const {}), isNull);
    });
  });

  test('pageTitleFor returns the entity-type label without needing a loaded '
      'TaxonomyDetail', () {
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
  });

  test('the attributes card title comes from the localizations, not a '
      'baked-in English word', () async {
    final de = await AppLocalizations.delegate.load(const Locale('de'));
    final detail = TaxonomyDetail(
      result: SearchResult(
        id: 'genus:carcharodon',
        name: 'Carcharodon',
        commonNames: const {},
        type: SearchEntityType.genus,
      ),
      commonNames: const {},
      classification: const [],
      metrics: const [],
      attributes: const [
        TaxonomyAttribute(key: 'body_shape', value: 'fusiform / normal'),
      ],
      isReferenceBacked: true,
    );

    final viewData = presenter.present(detail, Language.de, de);

    expect(viewData.attributesTitle, de.searchDetailAttributes);
    expect(viewData.attributesTitle, isNot('Attributes'));
  });
}
