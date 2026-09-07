import 'package:discere/enrichment/pipeline/repository/species_ownership_planner.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> workRow(
  String speciesId, {
  String? owner,
  bool wantsInatPhotos = false,
  bool wantsCommonNames = false,
}) => {
  'species_id': speciesId,
  'owner_deck_id': owner,
  'wants_inat_photos': wantsInatPhotos ? 1 : 0,
  'wants_common_names': wantsCommonNames ? 1 : 0,
};

Map<String, Object?> membershipRow(String speciesId, String deckId) => {
  'species_id': speciesId,
  'deck_id': deckId,
};

SpeciesOwnershipPlan planFor({
  required Map<String, Set<String>> decks,
  List<String>? priority,
  Map<String, bool> inatPhotos = const {},
  Map<String, bool> commonNames = const {},
  List<Map<String, Object?>> existingWork = const [],
  List<Map<String, Object?>> existingMembership = const [],
}) => SpeciesOwnershipPlanner(
  speciesIdsByDeckId: decks,
  prioritizedDeckIds: priority ?? decks.keys.toList(),
  includeInatPhotosByDeckId: inatPhotos,
  includeCommonNamesByDeckId: commonNames,
  existingSpeciesWorkRows: existingWork,
  existingMembershipRows: existingMembership,
).plan();

SpeciesOwnershipAssignment forSpecies(
  SpeciesOwnershipPlan plan,
  String speciesId,
) => plan.assignments.firstWhere((a) => a.speciesId == speciesId);

void main() {
  group('ownership', () {
    test('a species in one deck is owned by it', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
      );

      expect(forSpecies(plan, 'sp-a').ownerDeckId, 'deck-1');
      expect(forSpecies(plan, 'sp-a').deckIds, ['deck-1']);
    });

    test('a shared species goes to the higher-priority deck', () {
      final plan = planFor(
        decks: {
          'deck-2': {'sp-a'},
          'deck-1': {'sp-a'},
        },
        priority: ['deck-1', 'deck-2'],
      );

      expect(forSpecies(plan, 'sp-a').ownerDeckId, 'deck-1');
      // Both decks still reference it — ownership is about who enriches it,
      // not who may see it.
      expect(forSpecies(plan, 'sp-a').deckIds, ['deck-1', 'deck-2']);
    });

    test('an existing owner that still references the species keeps it', () {
      // Reassigning would strand whatever that deck already has in flight.
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
          'deck-2': {'sp-a'},
        },
        priority: ['deck-1', 'deck-2'],
        existingWork: [workRow('sp-a', owner: 'deck-2')],
      );

      expect(forSpecies(plan, 'sp-a').ownerDeckId, 'deck-2');
    });

    test('an owner that dropped out is replaced', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
        existingWork: [workRow('sp-a', owner: 'deck-gone')],
      );

      expect(forSpecies(plan, 'sp-a').ownerDeckId, 'deck-1');
    });

    test('the most widely shared species is assigned first', () {
      // Order decides who owns what: the deck that wins the shared species
      // is the highest-priority one holding it, not whoever came first
      // alphabetically.
      final plan = planFor(
        decks: {
          'deck-1': {'sp-rare', 'sp-shared'},
          'deck-2': {'sp-shared'},
          'deck-3': {'sp-shared'},
        },
        priority: ['deck-1', 'deck-2', 'deck-3'],
      );

      expect(plan.assignments.first.speciesId, 'sp-shared');
    });

    test('the result groups owned species by deck, including empty decks', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
          'deck-2': <String>{},
        },
        priority: ['deck-1', 'deck-2'],
      );

      final owned = plan.ownedSpeciesByDeckId(['deck-1', 'deck-2']);
      expect(owned['deck-1'], ['sp-a']);
      expect(owned['deck-2'], isEmpty);
    });
  });

  group('consent is additive', () {
    test('a deck missing from the map counts as consenting', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
      );

      expect(forSpecies(plan, 'sp-a').wantsInatPhotos, isTrue);
      expect(forSpecies(plan, 'sp-a').wantsCommonNames, isTrue);
    });

    test('one consenting deck is enough among several', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
          'deck-2': {'sp-a'},
        },
        priority: ['deck-1', 'deck-2'],
        inatPhotos: {'deck-1': false, 'deck-2': true},
      );

      expect(forSpecies(plan, 'sp-a').wantsInatPhotos, isTrue);
    });

    test('every deck opting out withholds consent', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
          'deck-2': {'sp-a'},
        },
        priority: ['deck-1', 'deck-2'],
        inatPhotos: {'deck-1': false, 'deck-2': false},
        commonNames: {'deck-1': false, 'deck-2': false},
      );

      expect(forSpecies(plan, 'sp-a').wantsInatPhotos, isFalse);
      expect(forSpecies(plan, 'sp-a').wantsCommonNames, isFalse);
    });

    test('stored consent survives a later opt-out', () {
      // Never a downgrade: a species already granted consent keeps it.
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
        inatPhotos: {'deck-1': false},
        commonNames: {'deck-1': false},
        existingWork: [
          workRow(
            'sp-a',
            owner: 'deck-1',
            wantsInatPhotos: true,
            wantsCommonNames: true,
          ),
        ],
      );

      expect(forSpecies(plan, 'sp-a').wantsInatPhotos, isTrue);
      expect(forSpecies(plan, 'sp-a').wantsCommonNames, isTrue);
    });

    test('the two flags are decided independently', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
        inatPhotos: {'deck-1': true},
        commonNames: {'deck-1': false},
      );

      expect(forSpecies(plan, 'sp-a').wantsInatPhotos, isTrue);
      expect(forSpecies(plan, 'sp-a').wantsCommonNames, isFalse);
    });
  });

  group('dropping species that left the plan', () {
    test('a species removed from its only deck is dropped', () {
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
        existingWork: [workRow('sp-a'), workRow('sp-gone')],
        existingMembership: [
          membershipRow('sp-a', 'deck-1'),
          membershipRow('sp-gone', 'deck-1'),
        ],
      );

      expect(plan.droppedSpeciesIds, ['sp-gone']);
    });

    test('a species held only by decks outside this plan is left alone', () {
      // This call knows nothing about deck-other and must not speak for it.
      final plan = planFor(
        decks: {
          'deck-1': {'sp-a'},
        },
        existingWork: [workRow('sp-a'), workRow('sp-elsewhere')],
        existingMembership: [
          membershipRow('sp-a', 'deck-1'),
          membershipRow('sp-elsewhere', 'deck-other'),
        ],
      );

      expect(plan.droppedSpeciesIds, isEmpty);
    });

    test('a species still referenced by another deck in the plan stays', () {
      final plan = planFor(
        decks: {
          'deck-1': <String>{},
          'deck-2': {'sp-a'},
        },
        priority: ['deck-1', 'deck-2'],
        existingWork: [workRow('sp-a', owner: 'deck-1')],
        existingMembership: [membershipRow('sp-a', 'deck-1')],
      );

      expect(plan.droppedSpeciesIds, isEmpty);
      expect(forSpecies(plan, 'sp-a').ownerDeckId, 'deck-2');
    });
  });

  test('a deck listed with no species produces no assignments', () {
    final plan = planFor(decks: {'deck-1': <String>{}});

    expect(plan.assignments, isEmpty);
    expect(plan.droppedSpeciesIds, isEmpty);
  });

  test('a species in a deck outside the priority list is ignored', () {
    // prioritizedDeckIds is what the caller is speaking for; a deck absent
    // from it is not part of this plan.
    final plan = planFor(
      decks: {
        'deck-1': {'sp-a'},
        'deck-untracked': {'sp-b'},
      },
      priority: ['deck-1'],
    );

    expect(plan.assignments.map((a) => a.speciesId), ['sp-a']);
  });
}
