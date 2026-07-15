import 'dart:math';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Species makeSpecies({
  required String id,
  required String genusScientificName,
  required String speciesScientificName,
  Map<Language, List<String>> speciesCommonNames = const {},
  String familyScientificName = 'Lamnidae',
  Map<Language, List<String>> familyCommonNames = const {},
}) {
  return Species(
    id,
    'ext-$id',
    'fishbase',
    speciesScientificName,
    speciesCommonNames,
    Classification(
      genusScientificName,
      const {},
      null,
      familyScientificName,
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
  const presenter = AnswerOptionsPresenter();

  group('AnswerOptionsPresenter.distinctPrimaryNames', () {
    test('returns one name per species when all names differ', () {
      final species = [
        makeSpecies(
          id: 'sp1',
          genusScientificName: 'Carcharodon',
          speciesScientificName: 'carcharias',
          speciesCommonNames: const {
            Language.de: ['Weißer Hai'],
          },
        ),
        makeSpecies(
          id: 'sp2',
          genusScientificName: 'Sphyrna',
          speciesScientificName: 'mokarran',
          speciesCommonNames: const {
            Language.de: ['Großer Hammerhai'],
          },
        ),
      ];

      final names = presenter.distinctPrimaryNames(
        species,
        Language.de,
        LearningMode.species,
      );

      expect(names, containsAll(['Weißer Hai', 'Großer Hammerhai']));
      expect(names, hasLength(2));
    });

    test('dedupes case-insensitively across species with the same name', () {
      final species = [
        makeSpecies(
          id: 'sp1',
          genusScientificName: 'Carcharodon',
          speciesScientificName: 'carcharias',
          speciesCommonNames: const {
            Language.de: ['Weißer Hai'],
          },
        ),
        makeSpecies(
          id: 'sp2',
          genusScientificName: 'Carcharodon',
          speciesScientificName: 'other',
          speciesCommonNames: const {
            Language.de: ['weißer hai'],
          },
        ),
      ];

      final names = presenter.distinctPrimaryNames(
        species,
        Language.de,
        LearningMode.species,
      );

      expect(names, ['Weißer Hai']);
    });

    test('falls back to the binomial name when no common name exists', () {
      final species = [
        makeSpecies(
          id: 'sp1',
          genusScientificName: 'Carcharodon',
          speciesScientificName: 'carcharias',
        ),
      ];

      final names = presenter.distinctPrimaryNames(
        species,
        Language.de,
        LearningMode.species,
      );

      expect(names, ['Carcharodon carcharias']);
    });

    test(
      'family mode produces far fewer distinct names for congeneric species',
      () {
        final species = [
          makeSpecies(
            id: 'sp1',
            genusScientificName: 'Carcharodon',
            speciesScientificName: 'carcharias',
            familyScientificName: 'Lamnidae',
            familyCommonNames: const {
              Language.de: ['Makrelenhaie'],
            },
          ),
          makeSpecies(
            id: 'sp2',
            genusScientificName: 'Isurus',
            speciesScientificName: 'oxyrinchus',
            familyScientificName: 'Lamnidae',
            familyCommonNames: const {
              Language.de: ['Makrelenhaie'],
            },
          ),
        ];

        final names = presenter.distinctPrimaryNames(
          species,
          Language.de,
          LearningMode.family,
        );

        expect(names, ['Makrelenhaie']);
      },
    );
  });

  group('AnswerOptionsPresenter.buildOptions', () {
    test('returns exactly 4 options with exactly one correct', () {
      final options = presenter.buildOptions(
        correctLabel: 'Weißer Hai',
        namePool: ['Weißer Hai', 'A', 'B', 'C', 'D'],
        random: Random(42),
      );

      expect(options, isNotNull);
      expect(options, hasLength(4));
      final correctOptions = options!.where((o) => o.isCorrect);
      expect(correctOptions, hasLength(1));
      expect(correctOptions.single.label, 'Weißer Hai');
    });

    test('excludes the correct label case-insensitively from distractors', () {
      // 'weißer hai' is a case-variant duplicate of the correct label and
      // must not be usable as a distractor, leaving only A/B/C (exactly
      // enough for the 3 required distractors).
      final options = presenter.buildOptions(
        correctLabel: 'Weißer Hai',
        namePool: ['weißer hai', 'A', 'B', 'C'],
        random: Random(1),
      );

      expect(options, isNotNull);
      expect(options!.where((o) => o.isCorrect), hasLength(1));
      expect(
        options.where((o) => o.label.toLowerCase() == 'weißer hai'),
        hasLength(1),
      );
    });

    test(
      'returns null when the correct label has a case-variant duplicate '
      'and too few real distractors remain',
      () {
        final options = presenter.buildOptions(
          correctLabel: 'Weißer Hai',
          namePool: ['weißer hai', 'A', 'B'],
          random: Random(1),
        );

        expect(options, isNull);
      },
    );

    test('returns null when fewer than 3 distinct distractors are available', () {
      final options = presenter.buildOptions(
        correctLabel: 'Weißer Hai',
        namePool: ['A', 'B'],
        random: Random(1),
      );

      expect(options, isNull);
    });

    test('returns exactly 4 options at the boundary of 3 distractors', () {
      final options = presenter.buildOptions(
        correctLabel: 'Weißer Hai',
        namePool: ['A', 'B', 'C'],
        random: Random(1),
      );

      expect(options, isNotNull);
      expect(options, hasLength(4));
      expect(
        options!.map((o) => o.label),
        containsAll(['Weißer Hai', 'A', 'B', 'C']),
      );
    });

    test('is deterministic given the same seeded Random', () {
      final namePool = ['Weißer Hai', 'A', 'B', 'C', 'D', 'E'];
      final first = presenter.buildOptions(
        correctLabel: 'Weißer Hai',
        namePool: namePool,
        random: Random(7),
      );
      final second = presenter.buildOptions(
        correctLabel: 'Weißer Hai',
        namePool: namePool,
        random: Random(7),
      );

      expect(
        first!.map((o) => o.label).toList(),
        second!.map((o) => o.label).toList(),
      );
    });
  });
}
