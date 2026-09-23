import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_update_diff.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// Covers DeckUpdateApplier — what a deck update would change against a
/// newer catalog version, and what applying the user's selection writes
/// back.

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
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDecksService mockDecksService;
  late MockSpeciesRepository mockSpeciesRepo;
  late DeckUpdateApplier applier;

  setUp(() {
    mockDecksService = MockDecksService();
    mockSpeciesRepo = MockSpeciesRepository();
    applier = DeckUpdateApplier(mockDecksService, mockSpeciesRepo);
  });

  group('DeckUpdateApplier', () {
    test(
      'diff reports added, removed and unresolved species',
      () async {
        final speciesA = _species('id-a', 'Genus', 'a');
        final speciesB = _species('id-b', 'Genus', 'b');
        final speciesC = _species('id-c', 'Genus', 'c');

        when(
          mockDecksService.getSpeciesByDeckId('deck-1'),
        ).thenAnswer((_) async => [speciesA, speciesB]);
        when(
          mockSpeciesRepo.resolveFullNames(['Genus a', 'Genus c', 'Genus x']),
        ).thenAnswer((_) async => {'Genus a': 'id-a', 'Genus c': 'id-c'});
        when(
          mockDecksService.getSpeciesByIds({'id-c'}),
        ).thenAnswer((_) async => [speciesC]);

        final remote = CreateDeck(
          name: 'Remote Deck',
          description: 'desc',
          speciesNames: {'Genus a', 'Genus c', 'Genus x'},
          sourceId: 'src-1',
          updatedAt: DateTime.utc(2026, 2, 1),
        );

        final diff = await applier.diff('deck-1', remote);

        expect(diff.addedSpecies.map((s) => s.id), ['id-c']);
        expect(diff.removedSpecies.map((s) => s.id), ['id-b']);
        expect(diff.unresolvedAddedNames, ['Genus x']);
        expect(diff.hasChanges, isTrue);
      },
    );

    test(
      'apply with additions only keeps existing species, adds new ones, bumps sourceId/updatedAt',
      () async {
        final diff = DeckUpdateDiff(
          addedSpecies: [_species('id-c', 'Genus', 'c')],
          removedSpecies: [_species('id-b', 'Genus', 'b')],
          unresolvedAddedNames: ['Genus x'],
        );
        final remote = CreateDeck(
          name: 'Remote Deck',
          description: 'desc',
          sourceId: 'src-new',
          updatedAt: DateTime.utc(2026, 2, 1),
        );
        when(mockDecksService.getCreateDeck('deck-1')).thenAnswer(
          (_) async => CreateDeck(
            id: 'deck-1',
            name: 'Local Deck',
            description: 'local desc',
            speciesIds: {'id-a', 'id-b'},
            sourceId: 'src-old',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        when(mockDecksService.updateDeck(any, any)).thenAnswer((_) async {});

        final unresolved = await applier.apply(
          deckId: 'deck-1',
          remote: remote,
          diff: diff,
          includeAdditions: true,
          includeRemovals: false,
        );

        expect(unresolved, ['Genus x']);
        final captured = verify(
          mockDecksService.updateDeck(captureAny, captureAny),
        ).captured;
        final updatedDeck = captured[0] as dynamic;
        final newSpeciesIds = captured[1] as Set<String>;
        expect(updatedDeck.name, 'Local Deck');
        expect(updatedDeck.description, 'local desc');
        expect(updatedDeck.sourceId, 'src-new');
        expect(updatedDeck.updatedAt, DateTime.utc(2026, 2, 1));
        expect(newSpeciesIds, {'id-a', 'id-b', 'id-c'});
      },
    );

    test(
      'apply with removals only drops species and returns no unresolved names',
      () async {
        final diff = DeckUpdateDiff(
          addedSpecies: [_species('id-c', 'Genus', 'c')],
          removedSpecies: [_species('id-b', 'Genus', 'b')],
          unresolvedAddedNames: ['Genus x'],
        );
        final remote = CreateDeck(
          name: 'Remote Deck',
          description: 'desc',
          sourceId: 'src-new',
          updatedAt: DateTime.utc(2026, 2, 1),
        );
        when(mockDecksService.getCreateDeck('deck-1')).thenAnswer(
          (_) async => CreateDeck(
            id: 'deck-1',
            name: 'Local Deck',
            description: 'local desc',
            speciesIds: {'id-a', 'id-b'},
            sourceId: 'src-old',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        when(mockDecksService.updateDeck(any, any)).thenAnswer((_) async {});

        final unresolved = await applier.apply(
          deckId: 'deck-1',
          remote: remote,
          diff: diff,
          includeAdditions: false,
          includeRemovals: true,
        );

        expect(unresolved, isEmpty);
        final captured = verify(
          mockDecksService.updateDeck(captureAny, captureAny),
        ).captured;
        final newSpeciesIds = captured[1] as Set<String>;
        expect(newSpeciesIds, {'id-a'});
      },
    );
  });
}
