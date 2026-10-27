import 'package:discere/learning/decks/edit/edit_deck_presenter.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/model/subdeck.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

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
  Set<String> activeSubdeckIds = const {},
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
    activeSubdeckIds: activeSubdeckIds,
  );
}

void main() {
  const presenter = EditDeckPresenter();

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

  test('isDirty detects a subdeck switched on or off', () {
    final saved = _draft(activeSubdeckIds: {'l1', 'l2'});
    expect(presenter.isDirty(_draft(activeSubdeckIds: {'l1'}), saved), isTrue);
    expect(
      presenter.isDirty(_draft(activeSubdeckIds: {'l2', 'l1'}), saved),
      isFalse,
    );
  });

  group('EditDeckPresenter subdecks', () {
    const bySpecies = {'sp-a': 'l1', 'sp-b': 'l2', 'sp-c': 'l2'};
    const subdecks = [
      Subdeck(deckId: 'd', id: 'l1', name: 'One', sortOrder: 0, isActive: true),
      Subdeck(deckId: 'd', id: 'l2', name: 'Two', sortOrder: 1, isActive: true),
    ];

    test('counts the species of each subdeck among the given ones', () {
      expect(
        presenter.subdeckSpeciesCounts({'sp-a', 'sp-c', 'sp-x'}, bySpecies),
        {'l1': 1, 'l2': 1},
      );
    });

    test('a species in no subdeck stands outside them', () {
      expect(
        presenter.hasSpeciesOutsideSubdecks({'sp-a', 'sp-x'}, bySpecies),
        isTrue,
      );
      expect(
        presenter.hasSpeciesOutsideSubdecks({'sp-a', 'sp-b'}, bySpecies),
        isFalse,
      );
    });

    test('the last subdeck on cannot be switched off while every species is '
        'in a subdeck', () {
      expect(
        presenter.canSwitchOffSubdeck(
          subdeckId: 'l1',
          activeSubdeckIds: {'l1'},
          hasSpeciesOutsideSubdecks: false,
        ),
        isFalse,
      );
      expect(
        presenter.canSwitchOffSubdeck(
          subdeckId: 'l1',
          activeSubdeckIds: {'l1', 'l2'},
          hasSpeciesOutsideSubdecks: false,
        ),
        isTrue,
      );
      expect(
        presenter.canSwitchOffSubdeck(
          subdeckId: 'l1',
          activeSubdeckIds: {'l1'},
          hasSpeciesOutsideSubdecks: true,
        ),
        isTrue,
      );
    });

    test('with none on and no species outside, every subdeck is on again', () {
      expect(
        presenter.effectiveActiveSubdecks(
          activeSubdeckIds: const {},
          subdecks: subdecks,
          hasSpeciesOutsideSubdecks: false,
        ),
        {'l1', 'l2'},
      );
      expect(
        presenter.effectiveActiveSubdecks(
          activeSubdeckIds: const {},
          subdecks: subdecks,
          hasSpeciesOutsideSubdecks: true,
        ),
        isEmpty,
      );
      expect(
        presenter.effectiveActiveSubdecks(
          activeSubdeckIds: const {'l2'},
          subdecks: subdecks,
          hasSpeciesOutsideSubdecks: false,
        ),
        {'l2'},
      );
    });
  });
}
