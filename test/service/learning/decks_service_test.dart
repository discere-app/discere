import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDeckRepository mockDeckRepo;
  late MockSpeciesRepository mockSpeciesRepo;
  late MockFlashcardStatRepository mockFlashcardStatRepo;
  late MockImageService mockImageService;
  late DecksService service;

  setUp(() {
    mockDeckRepo = MockDeckRepository();
    mockSpeciesRepo = MockSpeciesRepository();
    mockFlashcardStatRepo = MockFlashcardStatRepository();
    mockImageService = MockImageService();

    when(
      mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
    ).thenAnswer((_) async {});
    when(mockImageService.deleteImage(any)).thenAnswer((_) async {});
    when(
      mockFlashcardStatRepo.getSpeciesIdsByDeckId(any),
    ).thenAnswer((_) async => {});

    service = DecksService(
      mockDeckRepo,
      mockFlashcardStatRepo,
      mockSpeciesRepo,
      mockImageService,
    );
  });

  group('DecksService - createDeck', () {
    test('calls insertDeck on the repository', () async {
      final deck = CreateDeck(
        name: 'Test Deck',
        description: 'A test deck',
        speciesIds: {'1', '2'},
      );
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
          verify(
                mockFlashcardStatRepo.insertOrUpdateFlashcardStats(captureAny),
              ).captured.single
              as Set;
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

  group('DecksService - getAllDecks', () {
    test('returns ViewDecks built from repository data', () async {
      when(mockDeckRepo.getAllDecks()).thenAnswer(
        (_) async => [
          BaseDeck('d1', 'Deck 1', 'Description 1'),
          BaseDeck('d2', 'Deck 2', 'Description 2'),
        ],
      );
      when(
        mockFlashcardStatRepo.getDeckStat(any),
      ).thenAnswer((_) async => DeckStat(10, 0, 0));

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
