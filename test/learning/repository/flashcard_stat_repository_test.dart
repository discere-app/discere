import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/deck_lifecycle_observer.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late FlashcardStatRepository flashcardStatRepository;
  late DecksService decksService;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    flashcardStatRepository = FlashcardStatRepository(database: database);
    decksService = DecksService(
      DeckRepository(database: database),
      flashcardStatRepository,
      MockSpeciesRepository(),
      MockImageService(),
      deckConfigRepository: DeckConfigRepository(database: database),
      lifecycleObserver: const NoopDeckLifecycleObserver(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'getTotalDistinctSpeciesCount returns 0 for an empty database',
    () async {
      expect(await flashcardStatRepository.getTotalDistinctSpeciesCount(), 0);
    },
  );

  test('getTotalDistinctSpeciesCount counts each species once across decks, '
      'even when shared between them', () async {
    await decksService.createDeck(
      CreateDeck(name: 'Deck A', description: '', speciesIds: {'sp1', 'sp2'}),
    );
    await decksService.createDeck(
      CreateDeck(
        name: 'Deck B',
        // sp2 is shared with Deck A — must not be double-counted.
        description: '',
        speciesIds: {'sp2', 'sp3'},
      ),
    );

    expect(await flashcardStatRepository.getTotalDistinctSpeciesCount(), 3);
  });

  test('getDeckStat counts a species with no row for the mode as '
      'uninitialized, without the backfill having run', () async {
    final deckId = await decksService.createDeck(
      CreateDeck(
        name: 'Mode Switch Deck',
        description: '',
        speciesIds: {'sp1', 'sp2', 'sp3'},
      ),
    );

    // The deck was created in species mode and has rows only for it. Reading
    // the numbers for another mode must not depend on those rows existing yet:
    // the deck list renders before anything seeds them, and reporting a total
    // of zero there would show an untouched deck as fully learned.
    final familyStat = await flashcardStatRepository.getDeckStat(
      deckId,
      learningMode: LearningMode.family,
    );

    expect(familyStat.totalCount, 3);
    expect(familyStat.uninitializedCount, 3);
    expect(familyStat.dueCount, 0);
  });

  test('getDeckStat reports progress once cards of the mode are initialized',
      () async {
    final deckId = await decksService.createDeck(
      CreateDeck(
        name: 'Progress Deck',
        description: '',
        speciesIds: {'sp1', 'sp2', 'sp3', 'sp4'},
      ),
    );
    await flashcardStatRepository.insertOrUpdateFlashcardStats({
      FlashcardStat(
        speciesId: 'sp1',
        deckId: deckId,
        nextReviewDate: DateTime.now().subtract(const Duration(days: 1)),
      ),
    });

    final stat = await flashcardStatRepository.getDeckStat(deckId);

    expect(stat.totalCount, 4);
    expect(stat.uninitializedCount, 3);
    expect(stat.dueCount, 1, reason: 'the one initialized card is due');
  });
}
