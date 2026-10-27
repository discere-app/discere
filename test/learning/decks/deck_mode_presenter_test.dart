import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/deck_mode_presenter.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Species _species(String id, String genus, String epithet) {
  return Species(
    id,
    id,
    'fishbase',
    epithet,
    const {},
    Classification(
      genus,
      const {},
      null,
      'Family',
      const {},
      'Order',
      const {},
      'Class',
      const {},
      null,
    ),
    const [],
  );
}

void main() {
  const presenter = DeckModePresenter();

  group('DeckModePresenter.distinctNameCount / canUseMultipleChoice', () {
    test('counts distinct binomial names across species', () {
      final species = [
        _species('sp1', 'Genus1', 'one'),
        _species('sp2', 'Genus2', 'two'),
        _species('sp3', 'Genus3', 'three'),
      ];

      final count = presenter.distinctNameCount(
        species,
        Language.en,
        LearningMode.species,
        NameType.commonName,
      );

      expect(count, 3);
      expect(presenter.canUseMultipleChoice(count), isFalse);
    });

    test('canUseMultipleChoice is true once the count reaches the minimum', () {
      expect(
        presenter.canUseMultipleChoice(
          DeckModePresenter.minSpeciesForMultipleChoice,
        ),
        isTrue,
      );
      expect(
        presenter.canUseMultipleChoice(
          DeckModePresenter.minSpeciesForMultipleChoice - 1,
        ),
        isFalse,
      );
    });

    test('species not known yet have no count, which leaves multiple choice '
        'possible', () {
      final count = presenter.distinctNameCount(
        null,
        Language.en,
        LearningMode.species,
        NameType.commonName,
      );

      expect(count, isNull);
      expect(presenter.canUseMultipleChoice(count), isTrue);
    });
  });

  group('DeckModePresenter.effectiveReviewMode', () {
    test(
      'reverts multipleChoice to flip when there are not enough distinct names',
      () {
        final result = presenter.effectiveReviewMode(
          reviewMode: ReviewMode.multipleChoice,
          distinctNameCount: DeckModePresenter.minSpeciesForMultipleChoice - 1,
        );

        expect(result, ReviewMode.flip);
      },
    );

    test('keeps multipleChoice when there are enough distinct names', () {
      final result = presenter.effectiveReviewMode(
        reviewMode: ReviewMode.multipleChoice,
        distinctNameCount: DeckModePresenter.minSpeciesForMultipleChoice,
      );

      expect(result, ReviewMode.multipleChoice);
    });

    test('keeps multipleChoice while the count is not known yet', () {
      final result = presenter.effectiveReviewMode(
        reviewMode: ReviewMode.multipleChoice,
        distinctNameCount: null,
      );

      expect(result, ReviewMode.multipleChoice);
    });

    test('leaves flip mode untouched regardless of distinct name count', () {
      final result = presenter.effectiveReviewMode(
        reviewMode: ReviewMode.flip,
        distinctNameCount: 0,
      );

      expect(result, ReviewMode.flip);
    });
  });
}
