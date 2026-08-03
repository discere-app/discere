import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../mocks.mocks.dart';

/// Reproduces a suspected regression from 9909df0 ("enforce foreign keys so
/// deck deletion cascades"): `DeckRepository.insertDeck` upserts the `decks`
/// row via `conflictAlgorithm: replace`, which SQLite implements as
/// DELETE-then-INSERT. Now that `PRAGMA foreign_keys = ON` is actually
/// enforced, that DELETE fires `flashcard_stats`'s `ON DELETE CASCADE` to
/// `decks(id)` — wiping every species' review progress for the deck any time
/// something re-upserts the *same* deck row, e.g. `updateDeckCoverPath` after
/// the cover image finishes downloading, or `EditDeckPage` saving unrelated
/// metadata. Before 9909df0 this was a silent no-op (FK enforcement was
/// never actually on); now it silently deletes flashcard_stats correctly by
/// the enforcement's own logic, but the app never intended `insertDeck` to
/// mean "delete and recreate", so this shouldn't cascade.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late DecksService decksService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await rootBundle.loadString('assets/sql/user_db/tables/create_decks.sql'),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_flashcard_stats.sql',
      ),
    );
    // Mirrors DatabaseHelper.userDb's onOpen — enforcement only actually
    // fires once this pragma is set on the connection.
    await database.execute('PRAGMA foreign_keys = ON');

    decksService = DecksService(
      DeckRepository(database: database),
      FlashcardStatRepository(database: database),
      MockSpeciesRepository(),
      MockImageService(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'updateDeckCoverPath does not wipe out already-tracked species progress',
    () async {
      final deckId = await decksService.createDeck(
        CreateDeck(
          name: 'Critter',
          description: 'Imported online',
          speciesIds: {'sp1', 'sp2'},
        ),
      );
      expect(
        await decksService.getSpeciesIdsByDeckIds([deckId]),
        {'sp1', 'sp2'},
        reason: 'sanity check: species were tracked at creation',
      );

      await decksService.updateDeckCoverPath(deckId, '/tmp/cover.jpg');

      expect(
        await decksService.getSpeciesIdsByDeckIds([deckId]),
        {'sp1', 'sp2'},
        reason:
            'updateDeckCoverPath only touches coverImagePath — it must not '
            'delete flashcard_stats rows for species added earlier',
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
}
