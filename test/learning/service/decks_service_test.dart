import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/service/deck_lifecycle_observer.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDeckRepository mockDeckRepo;
  late MockSpeciesRepository mockSpeciesRepo;
  late MockFlashcardStatRepository mockFlashcardStatRepo;
  late MockImageService mockImageService;
  late MockDeckConfigRepository mockDeckConfigRepo;
  late DecksService service;

  setUp(() {
    mockDeckRepo = MockDeckRepository();
    mockSpeciesRepo = MockSpeciesRepository();
    mockFlashcardStatRepo = MockFlashcardStatRepository();
    mockImageService = MockImageService();
    mockDeckConfigRepo = MockDeckConfigRepository();

    when(
      mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
    ).thenAnswer((_) async {});
    when(mockImageService.deleteImage(any)).thenAnswer((_) async {});
    when(
      mockFlashcardStatRepo.getSpeciesIdsByDeckId(any),
    ).thenAnswer((_) async => {});
    when(
      mockFlashcardStatRepo.ensureStatsForLearningMode(any, any),
    ).thenAnswer((_) async {});
    when(mockDeckConfigRepo.getOrDefault(any)).thenAnswer(
      (inv) async => DeckConfig(deckId: inv.positionalArguments[0] as String),
    );

    service = DecksService(
      mockDeckRepo,
      mockFlashcardStatRepo,
      mockSpeciesRepo,
      mockImageService,
      deckConfigRepository: mockDeckConfigRepo,
      lifecycleObserver: const NoopDeckLifecycleObserver(),
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
        return d.id ?? 'new-id';
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
        return d.id ?? 'deck-id';
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
        return d.id ?? 'new-id';
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
          BaseDeck(id: 'd1', name: 'Deck 1', description: 'Description 1'),
          BaseDeck(id: 'd2', name: 'Deck 2', description: 'Description 2'),
        ],
      );
      when(
        mockFlashcardStatRepo.getDeckStat(any),
      ).thenAnswer((_) async => DeckStat(10, 0, 0));

      final result = await service.getAllDecks();

      expect(result.length, 2);
      expect(result.map((d) => d.name), containsAll(['Deck 1', 'Deck 2']));
    });

    test('computes progress and learningMode from the deck\'s configured mode, '
        'not always species', () async {
      when(
        mockDeckRepo.getAllDecks(),
      ).thenAnswer((_) async => [BaseDeck(id: 'd1', name: 'Deck 1', description: 'Description 1')]);
      when(mockDeckConfigRepo.getOrDefault('d1')).thenAnswer(
        (_) async =>
            const DeckConfig(deckId: 'd1', learningMode: LearningMode.family),
      );
      // Species-mode stats would report 0/10 learned; family-mode stats
      // (which must be what's actually queried) report 5/10 learned.
      when(
        mockFlashcardStatRepo.getDeckStat(
          'd1',
          learningMode: LearningMode.species,
        ),
      ).thenAnswer((_) async => DeckStat(10, 10, 0));
      when(
        mockFlashcardStatRepo.getDeckStat(
          'd1',
          learningMode: LearningMode.family,
        ),
      ).thenAnswer((_) async => DeckStat(10, 5, 0));

      final result = await service.getAllDecks();

      expect(result.single.learningMode, LearningMode.family);
      expect(result.single.progress, 0.5);
      verify(
        mockFlashcardStatRepo.ensureStatsForLearningMode(
          'd1',
          LearningMode.family,
        ),
      ).called(1);
    });
  });

  group('DecksService - deleteDeck', () {
    test('delegates to deckRepository.delete', () async {
      when(mockDeckRepo.delete('d1')).thenAnswer((_) async {});

      await service.deleteDeck('d1');

      verify(mockDeckRepo.delete('d1')).called(1);
    });

    test('tells its observer only once the repository delete is done', () async {
      var repositoryDeleteCompleted = false;
      var observerSawCompletedDelete = false;

      when(mockDeckRepo.delete('d1')).thenAnswer((_) async {
        repositoryDeleteCompleted = true;
      });

      final observer = _RecordingLifecycleObserver(
        onDeleted: (deckId) {
          expect(deckId, 'd1');
          observerSawCompletedDelete = repositoryDeleteCompleted;
        },
      );
      final observedService = DecksService(
        mockDeckRepo,
        mockFlashcardStatRepo,
        mockSpeciesRepo,
        mockImageService,
        deckConfigRepository: mockDeckConfigRepo,
        lifecycleObserver: observer,
      );

      await observedService.deleteDeck('d1');

      expect(repositoryDeleteCompleted, isTrue);
      expect(observerSawCompletedDelete, isTrue);
    });
  });

  group('DecksService - removeSpeciesFromDeck', () {
    test('deletes flashcard stats for just that species', () async {
      when(
        mockFlashcardStatRepo.deleteFlashcardStats('d1', {'sp1'}),
      ).thenAnswer((_) async {});

      await service.removeSpeciesFromDeck('d1', 'sp1');

      verify(
        mockFlashcardStatRepo.deleteFlashcardStats('d1', {'sp1'}),
      ).called(1);
    });

    test('notifies listeners', () async {
      when(
        mockFlashcardStatRepo.deleteFlashcardStats(any, any),
      ).thenAnswer((_) async {});
      var notified = false;
      service.addListener(() => notified = true);

      await service.removeSpeciesFromDeck('d1', 'sp1');

      expect(notified, isTrue);
    });
  });
}


/// Records what the service reports, so a test can assert on the order of a
/// mutation and the notification that follows it.
class _RecordingLifecycleObserver implements DeckLifecycleObserver {
  final void Function(String deckId) onDeleted;

  _RecordingLifecycleObserver({required this.onDeleted});

  @override
  void onDeckCreated(String deckId) {}

  @override
  void onDeckDeleted(String deckId) => onDeleted(deckId);
}
