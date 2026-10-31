import 'package:discere/learning/decks/edit/edit_deck_presenter.dart';
import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
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
  List<SubdeckHeading> subdecks = const [],
  Map<String, String> subdeckIdBySpeciesId = const {},
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
    subdecks: SubdeckDraft(
      subdecks: subdecks,
      subdeckIdBySpeciesId: subdeckIdBySpeciesId,
      activeSubdeckIds: activeSubdeckIds,
    ),
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

  group('EditDeckPresenter.effectiveActiveSubdecks', () {
    SubdeckDraft draft(
      Set<String> active, {
      Map<String, String> bySpecies = const {'a': 'l1'},
    }) => SubdeckDraft(
      subdecks: const [(id: 'l1', name: 'One'), (id: 'l2', name: 'Two')],
      subdeckIdBySpeciesId: bySpecies,
      activeSubdeckIds: active,
    );

    test('with none on and no species outside, every subdeck is on again', () {
      expect(presenter.effectiveActiveSubdecks(draft({}), {'a'}), {'l1', 'l2'});
    });

    test('a species outside is a card, so nothing changes', () {
      expect(presenter.effectiveActiveSubdecks(draft({}), {'a', 'x'}), isEmpty);
    });

    test('a subdeck on that holds a species is a card', () {
      expect(presenter.effectiveActiveSubdecks(draft({'l1'}), {'a'}), {'l1'});
    });

    test('only an empty subdeck on leaves no card, so every one is on', () {
      expect(presenter.effectiveActiveSubdecks(draft({'l2'}), {'a'}), {
        'l1',
        'l2',
      });
    });

    test('a deck without species keeps its switches', () {
      expect(
        presenter.effectiveActiveSubdecks(
          draft({}, bySpecies: const {}),
          const {},
        ),
        isEmpty,
      );
    });
  });
}
