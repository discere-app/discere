import 'package:discere/model/learning/base_deck.dart';
import 'package:discere/model/learning/deck_stat.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockDeckRepository mockDeckRepo;
  late MockSpeciesRepository mockSpeciesRepo;
  late MockFlashCardStatRepository mockFlashCardStatRepo;
  late DecksService service;

  setUp(() {
    mockDeckRepo = MockDeckRepository();
    mockSpeciesRepo = MockSpeciesRepository();
    mockFlashCardStatRepo = MockFlashCardStatRepository();

    // Default stub: insertOrUpdateFlashCardStats succeeds silently.
    when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
        .thenAnswer((_) async {});

    service = DecksService(
      mockDeckRepo,
      mockFlashCardStatRepo,
      mockSpeciesRepo,
    );
  });

  group('DecksService - createDeck', () {
    test('calls insertDeck on the repository', () async {
      final deck = CreateDeck(
        name: 'Test Deck',
        description: 'A test deck',
        speciesIds: {'1', '2'},
      );
      // The real insertDeck mutates deck.id via uuid, so simulate that.
      when(mockDeckRepo.insertDeck(any)).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as CreateDeck;
        d.id ??= 'new-id';
        return d.id!;
      });

      await service.createDeck(deck);

      verify(mockDeckRepo.insertDeck(deck)).called(1);
    });

    test('initializes flashcard stats for every species in the deck', () async {
      final deck = CreateDeck(
        name: 'Test Deck',
        description: 'A test deck',
        speciesIds: {'sp1', 'sp2', 'sp3'},
      );
      when(mockDeckRepo.insertDeck(any)).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as CreateDeck;
        d.id ??= 'deck-id';
        return d.id!;
      });

      await service.createDeck(deck);

      final captured =
          verify(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(captureAny))
              .captured
              .single as Set;
      expect(captured.length, 3);
    });

    test('notifies listeners after deck creation', () async {
      final deck = CreateDeck(
        name: 'Test Deck',
        description: 'A test deck',
        speciesIds: {},
      );
      when(mockDeckRepo.insertDeck(any)).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as CreateDeck;
        d.id ??= 'new-id';
        return d.id!;
      });

      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      await service.createDeck(deck);

      expect(notificationCount, 1);
    });
  });

  group('DecksService - createDeckBySpeciesScientificNames', () {
    test('does nothing when scientificNames list is empty', () async {
      await service.createDeckBySpeciesScientificNames('Name', 'Desc', []);

      verifyNever(mockDeckRepo.insertDeck(any));
      verifyNever(mockSpeciesRepo.getSpeciesIdsByScientificNames(any));
    });

    test('skips invalid names (wrong number of parts)', () async {
      // All names are invalid (single word or too many words).
      when(mockSpeciesRepo.getSpeciesIdsByScientificNames(any))
          .thenAnswer((_) async => {});
      when(mockDeckRepo.insertDeck(any)).thenAnswer((_) async => 'id');

      await service.createDeckBySpeciesScientificNames(
          'Name', 'Desc', ['InvalidName', 'Too Many Words Here']);

      // No valid names → nothing should be called on repos.
      verifyNever(mockSpeciesRepo.getSpeciesIdsByScientificNames(any));
      verifyNever(mockDeckRepo.insertDeck(any));
    });

    test('resolves valid scientific names to species IDs via repository',
        () async {
      when(mockSpeciesRepo.getSpeciesIdsByScientificNames(any))
          .thenAnswer((_) async => {'id1', 'id2'});
      when(mockDeckRepo.insertDeck(any)).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as CreateDeck;
        d.id ??= 'new-id';
        return d.id!;
      });

      await service.createDeckBySpeciesScientificNames(
        'Sharks',
        'Top sharks',
        ['Carcharodon carcharias', 'Galeocerdo cuvier'],
      );

      final capturedNames = verify(
              mockSpeciesRepo.getSpeciesIdsByScientificNames(captureAny))
          .captured
          .single as List;

      expect(capturedNames, containsAll([
        ('Carcharodon', 'carcharias'),
        ('Galeocerdo', 'cuvier'),
      ]));
    });

    test('creates deck with resolved species IDs', () async {
      when(mockSpeciesRepo.getSpeciesIdsByScientificNames(any))
          .thenAnswer((_) async => {'id1', 'id2'});
      when(mockDeckRepo.insertDeck(any)).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as CreateDeck;
        d.id ??= 'new-id';
        return d.id!;
      });

      await service.createDeckBySpeciesScientificNames(
        'Sharks',
        'Top sharks',
        ['Carcharodon carcharias'],
      );

      final captured =
          verify(mockDeckRepo.insertDeck(captureAny)).captured.single
              as CreateDeck;
      expect(captured.name, 'Sharks');
      expect(captured.speciesIds, containsAll(['id1', 'id2']));
    });

    test('creates empty deck when no species IDs are resolved', () async {
      when(mockSpeciesRepo.getSpeciesIdsByScientificNames(any))
          .thenAnswer((_) async => {});
      when(mockDeckRepo.insertDeck(any)).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as CreateDeck;
        d.id ??= 'new-id';
        return d.id!;
      });

      await service.createDeckBySpeciesScientificNames(
        'Empty Deck',
        'No matches',
        ['Genus species'],
      );

      final captured =
          verify(mockDeckRepo.insertDeck(captureAny)).captured.single
              as CreateDeck;
      expect(captured.speciesIds, isEmpty);
    });
  });

  group('DecksService - getAllDecks', () {
    test('returns ViewDecks built from repository data', () async {
      when(mockDeckRepo.getAllDecks()).thenAnswer((_) async => [
            BaseDeck('d1', 'Deck 1', 'Description 1'),
            BaseDeck('d2', 'Deck 2', 'Description 2'),
          ]);
      when(mockFlashCardStatRepo.getDeckStat(any))
          .thenAnswer((_) async => DeckStat(10, 0));

      final result = await service.getAllDecks();

      expect(result.length, 2);
      expect(result.map((d) => d.name), containsAll(['Deck 1', 'Deck 2']));
    });
  });

  group('DecksService - deleteDeck', () {
    test('delegates to deckRepository.delete', () async {
      when(mockDeckRepo.delete('d1')).thenAnswer((_) async {});

      await service.deleteDeck('d1');

      verify(mockDeckRepo.delete('d1')).called(1);
    });
  });
}
