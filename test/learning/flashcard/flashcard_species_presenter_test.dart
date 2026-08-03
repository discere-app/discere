import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Species makeSpecies({
  Map<Language, List<String>> speciesCommonNames = const {
    Language.de: ['Weißer Hai'],
    Language.en: ['Great white shark'],
  },
  Map<Language, List<String>> genusCommonNames = const {
    Language.de: ['Weiße Haie'],
  },
  Map<Language, List<String>> familyCommonNames = const {
    Language.de: ['Makrelenhaie'],
    Language.en: ['Mackerel sharks'],
  },
}) {
  return Species(
    'sp1',
    'ext1',
    'fishbase',
    'carcharias',
    speciesCommonNames,
    Classification(
      'Carcharodon',
      genusCommonNames,
      null,
      'Lamnidae',
      familyCommonNames,
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
  const presenter = FlashcardSpeciesPresenter();

  group('FlashcardSpeciesPresenter — species mode', () {
    test('shows the species common name and binomial name', () {
      final result = presenter.present(makeSpecies(), Language.de);

      expect(result.identity.primaryName, 'Weißer Hai');
      expect(result.identity.scientificName, 'Carcharodon carcharias');
    });

    test('falls back to the binomial name when no common name exists', () {
      final result = presenter.present(
        makeSpecies(speciesCommonNames: const {}),
        Language.de,
      );

      expect(result.identity.primaryName, 'Carcharodon carcharias');
    });
  });

  group('FlashcardSpeciesPresenter — nameType', () {
    test('scientificName always uses the scientific name, even when a common '
        'name exists', () {
      final result = presenter.present(
        makeSpecies(),
        Language.de,
        nameType: NameType.scientificName,
      );

      expect(result.identity.primaryName, 'Carcharodon carcharias');
      expect(result.identity.scientificName, 'Carcharodon carcharias');
    });

    test('scientificName combines with genus learning mode to quiz the genus '
        'scientific name', () {
      final result = presenter.present(
        makeSpecies(),
        Language.de,
        learningMode: LearningMode.genus,
        nameType: NameType.scientificName,
      );

      expect(result.identity.primaryName, 'Carcharodon');
    });

    test('commonName is the default and preserves the fallback behavior', () {
      final result = presenter.present(
        makeSpecies(speciesCommonNames: const {}),
        Language.de,
        nameType: NameType.commonName,
      );

      expect(result.identity.primaryName, 'Carcharodon carcharias');
    });
  });

  group('FlashcardSpeciesPresenter — genus mode', () {
    test('shows the genus common name and scientific name instead of the '
        'species names', () {
      final result = presenter.present(
        makeSpecies(),
        Language.de,
        learningMode: LearningMode.genus,
      );

      expect(result.identity.primaryName, 'Weiße Haie');
      expect(result.identity.scientificName, 'Carcharodon');
      expect(result.identity.commonNames, ['Weiße Haie']);
    });

    test('falls back to the genus scientific name when no genus common '
        'name exists at all', () {
      final result = presenter.present(
        makeSpecies(genusCommonNames: const {}),
        Language.de,
        learningMode: LearningMode.genus,
      );

      expect(result.identity.primaryName, 'Carcharodon');
    });
  });

  group('FlashcardSpeciesPresenter — family mode', () {
    test('shows the family common name and scientific name instead of the '
        'species names', () {
      final result = presenter.present(
        makeSpecies(),
        Language.de,
        learningMode: LearningMode.family,
      );

      expect(result.identity.primaryName, 'Makrelenhaie');
      expect(result.identity.scientificName, 'Lamnidae');
      expect(result.identity.commonNames, ['Makrelenhaie']);
    });

    test('falls back to English family common names when the requested '
        'language has none, same as species mode does', () {
      final result = presenter.present(
        makeSpecies(
          familyCommonNames: const {
            Language.en: ['Mackerel sharks'],
          },
        ),
        Language.de,
        learningMode: LearningMode.family,
      );

      expect(result.identity.primaryName, 'Mackerel sharks');
    });

    test('falls back to the family scientific name when no family common '
        'name exists at all', () {
      final result = presenter.present(
        makeSpecies(familyCommonNames: const {}),
        Language.de,
        learningMode: LearningMode.family,
      );

      expect(result.identity.primaryName, 'Lamnidae');
    });

    test('still exposes the full classification tree for the reveal, '
        'independent of the learning mode', () {
      final result = presenter.present(
        makeSpecies(),
        Language.de,
        learningMode: LearningMode.family,
      );

      expect(
        result.classificationRows.map((r) => r.scientificName),
        containsAll(['Carcharodon', 'Lamnidae', 'Lamniformes']),
      );
    });
  });
}
