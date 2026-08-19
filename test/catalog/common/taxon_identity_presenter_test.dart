import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Species makeSpecies({
  Map<Language, List<String>> commonNames = const {
    Language.de: ['Weißer Hai'],
    Language.en: ['Great white shark'],
  },
}) {
  return Species(
    'sp1',
    'ext1',
    'fishbase',
    'carcharias',
    commonNames,
    Classification(
      'Carcharodon',
      const {},
      null,
      'Lamnidae',
      const {},
      'Lamniformes',
      const {},
      'Chondrichthyes',
      const {},
      null,
    ),
    const [],
  );
}

void main() {
  const presenter = TaxonIdentityPresenter();

  test('uses the requested language\'s common name without flagging a '
      'fallback', () {
    final result = presenter.present(makeSpecies(), Language.de);

    expect(result.primaryName, 'Weißer Hai');
    expect(result.isEnglishFallback, isFalse);
  });

  test('flags an English fallback when the requested language has no '
      'common name', () {
    final result = presenter.present(
      makeSpecies(commonNames: const {Language.en: ['Great white shark']}),
      Language.de,
    );

    expect(result.primaryName, 'Great white shark');
    expect(result.isEnglishFallback, isTrue);
  });

  test('does not flag a fallback when there is no common name at all, '
      'since the binomial name is shown instead', () {
    final result = presenter.present(
      makeSpecies(commonNames: const {}),
      Language.de,
    );

    expect(result.primaryName, 'Carcharodon carcharias');
    expect(result.isEnglishFallback, isFalse);
  });
}
