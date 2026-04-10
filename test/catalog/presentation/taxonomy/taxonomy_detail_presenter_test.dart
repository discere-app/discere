import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/presenter/taxonomy_detail_presenter.dart';
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

  test('falls back to english common names when selected language is empty', () {
    final detail = TaxonomyDetail(
      result: SearchResult(
        id: 'family:lamnidae',
        name: 'Lamnidae',
        commonNames: const {
          Language.de: null,
          Language.en: 'Mackerel sharks; Mackerel sharks ; White sharks',
        },
        type: SearchEntityType.family,
      ),
      commonNames: const {
        Language.de: null,
        Language.en: 'Mackerel sharks; Mackerel sharks ; White sharks',
      },
      classification: const [],
      metrics: const [],
      isReferenceBacked: true,
    );

    final viewData = presenter.present(detail, Language.de, en);

    expect(viewData.pageTitle, 'Family');
    expect(viewData.primaryTitle, 'Mackerel sharks');
    expect(viewData.commonNames, ['Mackerel sharks', 'White sharks']);
  });

  test('maps metrics, classification labels, and attributes to display text', () {
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
  });
}
