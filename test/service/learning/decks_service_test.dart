import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/learning/base_deck.dart';
import 'package:discere/model/learning/deck_stat.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDeckRepository mockDeckRepo;
  late MockSpeciesRepository mockSpeciesRepo;
  late MockFlashCardStatRepository mockFlashCardStatRepo;
  late MockImageService mockImageService;
  late MockINaturalistService mockINatService;
  late MockINatPhotoCacheRepository mockINatCacheRepo;
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late DecksService service;

  setUp(() {
    mockDeckRepo = MockDeckRepository();
    mockSpeciesRepo = MockSpeciesRepository();
    mockFlashCardStatRepo = MockFlashCardStatRepository();
    mockImageService = MockImageService();
    mockINatService = MockINaturalistService();
    mockINatCacheRepo = MockINatPhotoCacheRepository();
    mockExternalIdRepo = MockExternalIdRepository();
    mockExternalIdCacheRepo = MockExternalIdCacheRepository();

    // Default stub: insertOrUpdateFlashCardStats succeeds silently.
    when(
      mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any),
    ).thenAnswer((_) async {});
    when(mockImageService.deleteImage(any)).thenAnswer((_) async {});

    // Stub getSpecies to return fake Species objects for whatever IDs are requested
    when(mockSpeciesRepo.getSpecies(any)).thenAnswer((inv) async {
      final ids = inv.positionalArguments[0] as Set<String>;
      return ids
          .map(
            (id) => Species(
              id,
              id,
              'mockSource',
              'mockName',
              {},
              Classification('', {}, null, '', {}, '', {}, '', {}, null),
              [],
            ),
          )
          .cast<Species>()
          .toSet();
    });

    service = DecksService(
      mockDeckRepo,
      mockFlashCardStatRepo,
      mockSpeciesRepo,
      mockImageService,
      mockINatService,
      mockINatCacheRepo,
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
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
          verify(
                mockFlashCardStatRepo.insertOrUpdateFlashCardStats(captureAny),
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
        mockFlashCardStatRepo.getDeckStat(any),
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
