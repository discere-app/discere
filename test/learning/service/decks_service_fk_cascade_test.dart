import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';

/// Reproduces a suspected regression from 9909df0 ("enforce foreign keys so
/// deck deletion cascades"): `DeckRepository.insertDeck` upserted the `decks`
/// row via `conflictAlgorithm: replace`, which SQLite implements as
/// DELETE-then-INSERT. Now that `PRAGMA foreign_keys = ON` is actually
/// enforced, that DELETE fired `flashcard_stats`'/`deck_config`'s
/// `ON DELETE CASCADE` to `decks(id)` — wiping every species' review
/// progress and the deck's FSRS settings any time something re-upserts the
/// *same* deck row, e.g. `updateDeckCoverPath` after the cover image
/// finishes downloading, or `updateDeck` saving unrelated metadata (the
/// `EditDeckPage` save path). Before 9909df0 this was a silent no-op (FK
/// enforcement was never actually on); now it silently deletes rows
/// correctly by the enforcement's own logic, but the app never intended
/// `insertDeck` to mean "delete and recreate", so this shouldn't cascade.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late DecksService decksService;
  late FlashcardStatRepository flashcardStatRepository;
  late DeckConfigRepository deckConfigRepository;

  setUp(() async {
    database = await openInMemoryUserDatabase();

    flashcardStatRepository = FlashcardStatRepository(database: database);
    deckConfigRepository = DeckConfigRepository(database: database);
    decksService = DecksService(
      DeckRepository(database: database),
      flashcardStatRepository,
      MockSpeciesRepository(),
      MockImageService(),
      deckConfigRepository: deckConfigRepository,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'updateDeckCoverPath does not wipe out already-tracked species progress '
    'or deck_config',
    () async {
      final deckId = await decksService.createDeck(
        CreateDeck(
          name: 'Critter',
          description: 'Imported online',
          speciesIds: {'sp1', 'sp2'},
        ),
      );
      // Non-default value, so a re-created (rather than truly preserved)
      // deck_config row — which would fall back to defaults — is caught.
      await deckConfigRepository.save(
        DeckConfig(deckId: deckId, desiredRetention: 0.75),
      );
      await flashcardStatRepository.insertOrUpdateFlashcardStats({
        FlashcardStat(
          speciesId: 'sp1',
          deckId: deckId,
          stability: 12.5,
          difficulty: 4.2,
        ),
      });

      await decksService.updateDeckCoverPath(deckId, '/tmp/cover.jpg');

      expect(
        await decksService.getSpeciesIdsByDeckIds([deckId]),
        {'sp1', 'sp2'},
        reason:
            'updateDeckCoverPath only touches coverImagePath — it must not '
            'delete flashcard_stats rows for species added earlier',
      );
      final sp1Stat = await flashcardStatRepository.getFlashcardStat(
        'sp1',
        deckId,
      );
      expect(
        sp1Stat?.stability,
        12.5,
        reason: 'existing review progress must survive, not just membership',
      );
      expect(
        (await deckConfigRepository.getOrDefault(deckId)).desiredRetention,
        0.75,
        reason:
            'deck_config hangs off the same decks(id) cascade as '
            'flashcard_stats and was silently reset by the same bug',
      );
    },
  );

  test(
    'a later addSpeciesToDeck call does not wipe out species added earlier',
    () async {
      final deckId = await decksService.createDeck(
        CreateDeck(
          name: 'Critter',
          description: 'Imported online',
          speciesIds: {'sp1'},
        ),
      );

      // Simulates a second, unrelated insertDeck upsert happening in between
      // — e.g. the deck's sort order being touched, or any other save.
      await decksService.updateDeckCoverPath(deckId, '/tmp/cover.jpg');
      await decksService.addSpeciesToDeck(deckId, {'sp2'});

      expect(
        await decksService.getSpeciesIdsByDeckIds([deckId]),
        {'sp1', 'sp2'},
        reason:
            'both the originally-imported species and the one resolved '
            'later via iNat should still be tracked',
      );
    },
  );

  group('updateDeck (the Edit Deck save path)', () {
    test(
      'saving unrelated deck metadata preserves progress for species not '
      'touched by the species diff',
      () async {
        final deckId = await decksService.createDeck(
          CreateDeck(
            name: 'Critter',
            description: 'Imported online',
            speciesIds: {'sp1', 'sp2'},
          ),
        );
        await deckConfigRepository.save(
          DeckConfig(deckId: deckId, desiredRetention: 0.75),
        );
        await flashcardStatRepository.insertOrUpdateFlashcardStats({
          FlashcardStat(
            speciesId: 'sp1',
            deckId: deckId,
            stability: 12.5,
            difficulty: 4.2,
          ),
        });

        final decks = await decksService.getAllDecks();
        final baseDeck = decks.single;
        baseDeck.name = 'Critter (renamed)';

        // Same species set — a pure metadata edit, nothing added/removed.
        await decksService.updateDeck(baseDeck, {'sp1', 'sp2'});

        final sp1Stat = await flashcardStatRepository.getFlashcardStat(
          'sp1',
          deckId,
        );
        expect(
          sp1Stat?.stability,
          12.5,
          reason:
              'renaming the deck must not reset an untouched species\' FSRS '
              'progress',
        );
        expect(
          (await deckConfigRepository.getOrDefault(deckId)).desiredRetention,
          0.75,
        );
      },
    );
  });
}
