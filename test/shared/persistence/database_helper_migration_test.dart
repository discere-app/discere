import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pre-v6 schema, as it existed in production before the learning_mode
/// column/composite-key migration was introduced.
const _legacyDecksSql = '''
CREATE TABLE decks (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  description     TEXT,
  coverImagePath  TEXT,
  language        INTEGER NOT NULL DEFAULT 1
)
''';

const _legacyDeckConfigSql = '''
CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  new_cards_per_day    INTEGER DEFAULT 20,
  max_reviews_per_day  INTEGER DEFAULT 200
)
''';

const _legacyFlashcardStatsSql = '''
CREATE TABLE flashcard_stats (
  species_id       TEXT NOT NULL,
  deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  next_review_date INTEGER,
  stability        REAL    DEFAULT 0.0,
  difficulty       REAL    DEFAULT 0.0,
  last_review_date INTEGER,
  card_state       INTEGER DEFAULT 0,
  step_index       INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, species_id)
)
''';

const _legacyDailyCountsSql = '''
CREATE TABLE IF NOT EXISTS daily_counts (
  deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  date         TEXT    NOT NULL,
  new_count    INTEGER DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, date)
)
''';

/// v6 schema, as it existed before the review_mode column (multiple-choice
/// review) was introduced.
const _v6DeckConfigSql = '''
CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  new_cards_per_day    INTEGER DEFAULT 20,
  max_reviews_per_day  INTEGER DEFAULT 200,
  learning_mode        TEXT    NOT NULL DEFAULT 'species'
)
''';

/// v8 schema, as it existed before the name_type column/composite-key
/// migration was introduced.
const _v8DeckConfigSql = '''
CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  new_cards_per_day    INTEGER DEFAULT 20,
  max_reviews_per_day  INTEGER DEFAULT 200,
  learning_mode        TEXT    NOT NULL DEFAULT 'species',
  review_mode          TEXT    NOT NULL DEFAULT 'flip'
)
''';

const _v8FlashcardStatsSql = '''
CREATE TABLE flashcard_stats (
  species_id       TEXT NOT NULL,
  deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  learning_mode    TEXT NOT NULL DEFAULT 'species',
  next_review_date INTEGER,
  stability        REAL    DEFAULT 0.0,
  difficulty       REAL    DEFAULT 0.0,
  last_review_date INTEGER,
  card_state       INTEGER DEFAULT 0,
  step_index       INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, species_id, learning_mode)
)
''';

const _v8DailyCountsSql = '''
CREATE TABLE IF NOT EXISTS daily_counts (
  deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  date         TEXT    NOT NULL,
  learning_mode TEXT   NOT NULL DEFAULT 'species',
  new_count    INTEGER DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, date, learning_mode)
)
''';

/// v10 schema, as it existed before the daily new-card/review limits
/// (new_cards_per_day, max_reviews_per_day, daily_counts) were removed.
const _v10DeckConfigSql = '''
CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  new_cards_per_day    INTEGER DEFAULT 20,
  max_reviews_per_day  INTEGER DEFAULT 200,
  learning_mode        TEXT    NOT NULL DEFAULT 'species',
  name_type            TEXT    NOT NULL DEFAULT 'commonName',
  review_mode          TEXT    NOT NULL DEFAULT 'flip'
)
''';

const _v10DailyCountsSql = '''
CREATE TABLE IF NOT EXISTS daily_counts (
  deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  date         TEXT    NOT NULL,
  learning_mode TEXT   NOT NULL DEFAULT 'species',
  name_type    TEXT    NOT NULL DEFAULT 'commonName',
  new_count    INTEGER DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, date, learning_mode, name_type)
)
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'migrating v5 -> v6 preserves existing progress as species-mode data',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 5);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.execute(_legacyDeckConfigSql);
      await db.execute(_legacyFlashcardStatsSql);
      await db.execute(_legacyDailyCountsSql);

      await db.insert('decks', {'id': 'deck-1', 'name': 'Test Deck'});
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.85,
      });
      await db.insert('flashcard_stats', {
        'species_id': 'species-1',
        'deck_id': 'deck-1',
        'next_review_date': 1000,
        'stability': 4.2,
        'difficulty': 3.1,
        'last_review_date': 500,
        'card_state': 2,
        'step_index': 0,
      });
      await db.insert('daily_counts', {
        'deck_id': 'deck-1',
        'date': '2026-07-14',
        'new_count': 3,
        'review_count': 7,
      });

      await DatabaseHelper.migrateUserSchemaV5ToV6ForTesting(db);

      final deckConfigRows = await db.query('deck_config');
      expect(deckConfigRows, hasLength(1));
      expect(deckConfigRows.single['learning_mode'], 'species');
      expect(deckConfigRows.single['desired_retention'], 0.85);

      final flashcardStatRows = await db.query('flashcard_stats');
      expect(flashcardStatRows, hasLength(1));
      final stat = flashcardStatRows.single;
      expect(stat['species_id'], 'species-1');
      expect(stat['deck_id'], 'deck-1');
      expect(stat['learning_mode'], 'species');
      expect(stat['next_review_date'], 1000);
      expect(stat['stability'], 4.2);
      expect(stat['difficulty'], 3.1);
      expect(stat['last_review_date'], 500);
      expect(stat['card_state'], 2);

      final dailyCountRows = await db.query('daily_counts');
      expect(dailyCountRows, hasLength(1));
      final dailyCount = dailyCountRows.single;
      expect(dailyCount['learning_mode'], 'species');
      expect(dailyCount['new_count'], 3);
      expect(dailyCount['review_count'], 7);

      // A second flashcard_stats row for the same species can now coexist
      // under a different learning mode thanks to the composite primary key.
      await db.insert('flashcard_stats', {
        'species_id': 'species-1',
        'deck_id': 'deck-1',
        'learning_mode': 'family',
      });
      final rowsAfterFamilyInsert = await db.query(
        'flashcard_stats',
        where: 'species_id = ? AND deck_id = ?',
        whereArgs: ['species-1', 'deck-1'],
      );
      expect(rowsAfterFamilyInsert, hasLength(2));
    },
  );

  test(
    'migrating v6 -> v7 adds review_mode with a flip default, preserving '
    'existing rows',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 6);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.execute(_v6DeckConfigSql);

      await db.insert('decks', {'id': 'deck-1', 'name': 'Test Deck'});
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.85,
        'learning_mode': 'family',
      });

      await DatabaseHelper.migrateUserSchemaV6ToV7ForTesting(db);

      final rows = await db.query('deck_config');
      expect(rows, hasLength(1));
      expect(rows.single['deck_id'], 'deck-1');
      expect(rows.single['desired_retention'], 0.85);
      expect(rows.single['learning_mode'], 'family');
      expect(rows.single['review_mode'], 'flip');
    },
  );

  test(
    'migrating v7 -> v8 adds sortOrder to decks, backfilled by creation order',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 7);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.insert('decks', {'id': 'deck-1', 'name': 'First'});
      await db.insert('decks', {'id': 'deck-2', 'name': 'Second'});
      await db.insert('decks', {'id': 'deck-3', 'name': 'Third'});

      await DatabaseHelper.migrateUserSchemaV7ToV8ForTesting(db);

      final rows = await db.query('decks', orderBy: 'sortOrder ASC');
      expect(rows.map((row) => row['id']), ['deck-1', 'deck-2', 'deck-3']);
      expect(rows.map((row) => row['sortOrder']), [1, 2, 3]);
    },
  );

  test(
    'migrating v8 -> v9 preserves existing progress as commonName-type data',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 8);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.execute(_v8DeckConfigSql);
      await db.execute(_v8FlashcardStatsSql);
      await db.execute(_v8DailyCountsSql);

      await db.insert('decks', {'id': 'deck-1', 'name': 'Test Deck'});
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.85,
        'learning_mode': 'genus',
      });
      await db.insert('flashcard_stats', {
        'species_id': 'species-1',
        'deck_id': 'deck-1',
        'learning_mode': 'genus',
        'next_review_date': 1000,
        'stability': 4.2,
        'difficulty': 3.1,
        'last_review_date': 500,
        'card_state': 2,
        'step_index': 0,
      });
      await db.insert('daily_counts', {
        'deck_id': 'deck-1',
        'date': '2026-07-14',
        'learning_mode': 'genus',
        'new_count': 3,
        'review_count': 7,
      });

      await DatabaseHelper.migrateUserSchemaV8ToV9ForTesting(db);

      final deckConfigRows = await db.query('deck_config');
      expect(deckConfigRows, hasLength(1));
      expect(deckConfigRows.single['learning_mode'], 'genus');
      expect(deckConfigRows.single['name_type'], 'commonName');
      expect(deckConfigRows.single['desired_retention'], 0.85);

      final flashcardStatRows = await db.query('flashcard_stats');
      expect(flashcardStatRows, hasLength(1));
      final stat = flashcardStatRows.single;
      expect(stat['species_id'], 'species-1');
      expect(stat['deck_id'], 'deck-1');
      expect(stat['learning_mode'], 'genus');
      expect(stat['name_type'], 'commonName');
      expect(stat['next_review_date'], 1000);
      expect(stat['stability'], 4.2);
      expect(stat['difficulty'], 3.1);
      expect(stat['last_review_date'], 500);
      expect(stat['card_state'], 2);

      final dailyCountRows = await db.query('daily_counts');
      expect(dailyCountRows, hasLength(1));
      final dailyCount = dailyCountRows.single;
      expect(dailyCount['learning_mode'], 'genus');
      expect(dailyCount['name_type'], 'commonName');
      expect(dailyCount['new_count'], 3);
      expect(dailyCount['review_count'], 7);

      // A second flashcard_stats row for the same species/mode can now
      // coexist under a different name_type thanks to the composite key.
      await db.insert('flashcard_stats', {
        'species_id': 'species-1',
        'deck_id': 'deck-1',
        'learning_mode': 'genus',
        'name_type': 'scientificName',
      });
      final rowsAfterScientificInsert = await db.query(
        'flashcard_stats',
        where: 'species_id = ? AND deck_id = ?',
        whereArgs: ['species-1', 'deck-1'],
      );
      expect(rowsAfterScientificInsert, hasLength(2));
    },
  );

  test(
    'migrating v9 -> v10 adds sourceId and updatedAt to decks, nullable for '
    'existing rows',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 9);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.insert('decks', {'id': 'deck-1', 'name': 'Existing Deck'});

      await DatabaseHelper.migrateUserSchemaV9ToV10ForTesting(db);

      final rows = await db.query('decks');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'deck-1');
      expect(rows.single['sourceId'], isNull);
      expect(rows.single['updatedAt'], isNull);

      await db.update(
        'decks',
        {'sourceId': 'catalog-uuid-1', 'updatedAt': 1752000000000},
        where: 'id = ?',
        whereArgs: ['deck-1'],
      );
      final updatedRows = await db.query('decks');
      expect(updatedRows.single['sourceId'], 'catalog-uuid-1');
      expect(updatedRows.single['updatedAt'], 1752000000000);
    },
  );

  test(
    'migrating v10 -> v11 drops the daily new-card/review limits, preserving '
    'the remaining deck_config columns',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 10);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.execute(_v10DeckConfigSql);
      await db.execute(_v10DailyCountsSql);

      await db.insert('decks', {'id': 'deck-1', 'name': 'Test Deck'});
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.85,
        'new_cards_per_day': 5,
        'max_reviews_per_day': 50,
        'learning_mode': 'genus',
        'name_type': 'scientificName',
        'review_mode': 'multipleChoice',
      });
      await db.insert('daily_counts', {
        'deck_id': 'deck-1',
        'date': '2026-07-23',
        'learning_mode': 'genus',
        'name_type': 'scientificName',
        'new_count': 20,
        'review_count': 2,
      });

      await DatabaseHelper.migrateUserSchemaV10ToV11ForTesting(db);

      final deckConfigRows = await db.query('deck_config');
      expect(deckConfigRows, hasLength(1));
      final config = deckConfigRows.single;
      expect(config['deck_id'], 'deck-1');
      expect(config['desired_retention'], 0.85);
      expect(config['learning_mode'], 'genus');
      expect(config['name_type'], 'scientificName');
      expect(config['review_mode'], 'multipleChoice');
      expect(config.containsKey('new_cards_per_day'), isFalse);
      expect(config.containsKey('max_reviews_per_day'), isFalse);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'daily_counts'",
      );
      expect(tables, isEmpty);
    },
  );
}
