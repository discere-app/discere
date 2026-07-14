import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Species makeSpecies({
  Map<Language, List<String>> commonNames = const {
    Language.de: ['Weißer Hai'],
  },
  String? superClass = 'Gnathostomata',
}) {
  return Species(
    'sp1',
    'ext1',
    'fishbase',
    'carcharias',
    commonNames,
    Classification(
      'Carcharodon',
      const {Language.de: ['Weiße Haie']},
      null,
      'Lamnidae',
      const {Language.de: ['Makrelenhaie']},
      'Lamniformes',
      const {Language.de: ['Makrelenhaiartige']},
      'Chondrichthyes',
      const {Language.de: ['Knorpelfische']},
      superClass,
    ),
    const [],
  );
}

void main() {
  const presenter = TaxonClassificationPresenter();

  test('includes the species itself as the most specific rank', () {
    final rows = presenter.present(makeSpecies(), Language.de);

    expect(rows.first.type, ClassificationRowType.species);
    expect(rows.first.scientificName, 'Carcharodon carcharias');
    expect(rows.first.commonName, 'Weißer Hai');
    expect(rows.first.id, 'sp1');
  });

  test(
    'lists the full path in descending specificity: species, genus, '
    'family, order, class, superclass',
    () {
      final rows = presenter.present(makeSpecies(), Language.de);

      expect(rows.map((r) => r.type), [
        ClassificationRowType.species,
        ClassificationRowType.genus,
        ClassificationRowType.family,
        ClassificationRowType.order,
        ClassificationRowType.classType,
        ClassificationRowType.superClass,
      ]);
    },
  );

  test('omits the superclass row when the species has none', () {
    final rows = presenter.present(makeSpecies(superClass: null), Language.de);

    expect(rows.map((r) => r.type), isNot(contains(ClassificationRowType.superClass)));
  });

  test('falls back to the binomial name when the species has no common name', () {
    final rows = presenter.present(
      makeSpecies(commonNames: const {}),
      Language.de,
    );

    expect(rows.first.commonName, isNull);
    expect(rows.first.scientificName, 'Carcharodon carcharias');
  });
}
