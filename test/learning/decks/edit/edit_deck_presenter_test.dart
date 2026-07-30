import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/edit/edit_deck_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
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

EditDeckDraft _draft({
  String name = 'Deck',
  String description = 'Description',
  String? coverImagePath,
  Language language = Language.en,
  double desiredRetention = 0.9,
  LearningMode learningMode = LearningMode.species,
  NameType nameType = NameType.commonName,
  ReviewMode reviewMode = ReviewMode.flip,
  Set<String> speciesIds = const {},
}) {
  return EditDeckDraft(
    name: name,
    description: description,
    coverImagePath: coverImagePath,
    language: language,
    desiredRetention: desiredRetention,
    learningMode: learningMode,
    nameType: nameType,
    reviewMode: reviewMode,
    speciesIds: speciesIds,
  );
}

void main() {
  const presenter = EditDeckPresenter();

  group('EditDeckPresenter.distinctNameCount / canUseMultipleChoice', () {
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
          EditDeckPresenter.minSpeciesForMultipleChoice,
        ),
        isTrue,
      );
      expect(
        presenter.canUseMultipleChoice(
          EditDeckPresenter.minSpeciesForMultipleChoice - 1,
        ),
        isFalse,
      );
    });
  });

  group('EditDeckPresenter.effectiveReviewMode', () {
    test(
      'reverts multipleChoice to flip when there are not enough distinct names',
      () {
        final result = presenter.effectiveReviewMode(
          reviewMode: ReviewMode.multipleChoice,
          distinctNameCount: EditDeckPresenter.minSpeciesForMultipleChoice - 1,
        );

        expect(result, ReviewMode.flip);
      },
    );

    test('keeps multipleChoice when there are enough distinct names', () {
      final result = presenter.effectiveReviewMode(
        reviewMode: ReviewMode.multipleChoice,
        distinctNameCount: EditDeckPresenter.minSpeciesForMultipleChoice,
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

  group('EditDeckPresenter.isDirty', () {
    test('returns false when current equals saved', () {
      final draft = _draft(speciesIds: {'sp1', 'sp2'});
      expect(presenter.isDirty(draft, draft), isFalse);
    });

    test('name and description differences are trimmed before comparing', () {
      final saved = _draft(name: 'Deck', description: 'Description');
      final current = _draft(name: '  Deck  ', description: '  Description  ');
      expect(presenter.isDirty(current, saved), isFalse);
    });

    test('detects a real name change', () {
      final saved = _draft(name: 'Deck');
      final current = _draft(name: 'Renamed Deck');
      expect(presenter.isDirty(current, saved), isTrue);
    });

    test('speciesIds comparison is order-independent (set semantics)', () {
      final saved = _draft(speciesIds: {'sp1', 'sp2', 'sp3'});
      final current = _draft(speciesIds: {'sp3', 'sp1', 'sp2'});
      expect(presenter.isDirty(current, saved), isFalse);
    });

    test('detects an added species', () {
      final saved = _draft(speciesIds: {'sp1', 'sp2'});
      final current = _draft(speciesIds: {'sp1', 'sp2', 'sp3'});
      expect(presenter.isDirty(current, saved), isTrue);
    });

    test('detects a removed species even when the count stays the same', () {
      final saved = _draft(speciesIds: {'sp1', 'sp2'});
      final current = _draft(speciesIds: {'sp1', 'sp3'});
      expect(presenter.isDirty(current, saved), isTrue);
    });

    test('detects a reviewMode change', () {
      final saved = _draft(reviewMode: ReviewMode.flip);
      final current = _draft(reviewMode: ReviewMode.multipleChoice);
      expect(presenter.isDirty(current, saved), isTrue);
    });

    test('detects a coverImagePath change including null <-> non-null', () {
      final saved = _draft(coverImagePath: null);
      final current = _draft(coverImagePath: '/path/to/cover.jpg');
      expect(presenter.isDirty(current, saved), isTrue);
    });
  });
}
