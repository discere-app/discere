import 'dart:convert';

import 'package:discere/shared/persistence/user_db_schema.dart';
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

/// Current (post-v11) schema, unchanged by v13 — v13 only prunes rows, it
/// doesn't alter these tables.
const _currentDeckConfigSql = '''
CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  learning_mode        TEXT    NOT NULL DEFAULT 'species',
  name_type            TEXT    NOT NULL DEFAULT 'commonName',
  review_mode          TEXT    NOT NULL DEFAULT 'flip'
)
''';

const _currentFlashcardStatsSql = '''
CREATE TABLE IF NOT EXISTS flashcard_stats (
  species_id       TEXT NOT NULL,
  deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  learning_mode    TEXT NOT NULL DEFAULT 'species',
  name_type        TEXT NOT NULL DEFAULT 'commonName',
  next_review_date INTEGER,
  stability        REAL    DEFAULT 0.0,
  difficulty       REAL    DEFAULT 0.0,
  last_review_date INTEGER,
  card_state       INTEGER DEFAULT 0,
  step_index       INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, species_id, learning_mode, name_type)
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

/// v11 schema, as it existed before the producer-consumer enrichment rewrite
/// introduced the species-capability-queue/deck-membership/unresolved-names
/// tables and the wants_inat_photos/wants_common_names consent columns.
const _v11EnrichmentJobsSql = '''
CREATE TABLE IF NOT EXISTS enrichment_jobs (
  deck_id             TEXT PRIMARY KEY,
  status              TEXT NOT NULL,
  attempted_at        INTEGER,
  completed_at        INTEGER,
  current_stage       TEXT,
  payload_json        TEXT NOT NULL,
  failure_kind        TEXT,
  last_error          TEXT,
  progress_completed  INTEGER NOT NULL DEFAULT 0,
  progress_total      INTEGER NOT NULL DEFAULT 0,
  retry_count         INTEGER NOT NULL DEFAULT 0,
  next_attempt_at     INTEGER,
  lease_owner         TEXT,
  lease_expires_at    INTEGER,
  updated_at          INTEGER NOT NULL
)
''';

const _v11EnrichmentSpeciesWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_species_work (
  species_id                  TEXT PRIMARY KEY,
  owner_deck_id               TEXT NOT NULL,
  deck_ids_json               TEXT NOT NULL,
  deck_count                  INTEGER NOT NULL DEFAULT 0,
  base_state                  TEXT NOT NULL DEFAULT 'pending',
  inat_primary_state          TEXT NOT NULL DEFAULT 'pending',
  species_common_names_state  TEXT NOT NULL DEFAULT 'pending',
  inat_backfill_state         TEXT NOT NULL DEFAULT 'pending',
  updated_at                  INTEGER NOT NULL
)
''';

/// True v11 taxonomy shape — before step 1 adds the retry columns and before
/// the later steps drop owner_deck_id/deck_ids_json/species_ids_json/rank/
/// scientific_name.
const _v11EnrichmentTaxonomyWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key             TEXT PRIMARY KEY,
  runtime_entity_key   TEXT NOT NULL UNIQUE,
  owner_deck_id        TEXT NOT NULL,
  deck_ids_json        TEXT NOT NULL,
  species_ids_json     TEXT NOT NULL,
  rank                 TEXT NOT NULL,
  scientific_name      TEXT NOT NULL,
  common_names_state   TEXT NOT NULL DEFAULT 'pending',
  updated_at           INTEGER NOT NULL
)
''';

const _v12EnrichmentSpeciesWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_species_work (
  species_id                  TEXT PRIMARY KEY,
  owner_deck_id               TEXT NOT NULL,
  deck_ids_json               TEXT NOT NULL,
  deck_count                  INTEGER NOT NULL DEFAULT 0,
  base_state                  TEXT NOT NULL DEFAULT 'pending',
  inat_primary_state          TEXT NOT NULL DEFAULT 'pending',
  species_common_names_state  TEXT NOT NULL DEFAULT 'pending',
  inat_backfill_state         TEXT NOT NULL DEFAULT 'pending',
  wants_inat_photos           INTEGER NOT NULL DEFAULT 0,
  wants_common_names          INTEGER NOT NULL DEFAULT 0,
  updated_at                  INTEGER NOT NULL
)
''';

/// Already-shrunk (v13) shape — used to verify the v12 -> v13 migration is a
/// harmless no-op when a fresh/very-old install jumps straight to v13 with
/// nothing left to rename-recreate-copy.
const _v13EnrichmentSpeciesWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_species_work (
  species_id          TEXT PRIMARY KEY,
  owner_deck_id       TEXT NOT NULL,
  deck_count          INTEGER NOT NULL DEFAULT 0,
  wants_inat_photos   INTEGER NOT NULL DEFAULT 0,
  wants_common_names  INTEGER NOT NULL DEFAULT 0,
  updated_at          INTEGER NOT NULL
)
''';

const _v12EnrichmentJobStagesSql = '''
CREATE TABLE IF NOT EXISTS enrichment_job_stages (
  deck_id TEXT NOT NULL,
  stage   TEXT NOT NULL,
  state   TEXT NOT NULL,
  PRIMARY KEY (deck_id, stage)
)
''';

/// Pre-v14 shape, with the `owner_deck_id` column later dropped since
/// nothing ever reads it for claiming work.
const _v13EnrichmentTaxonomyWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key             TEXT PRIMARY KEY,
  runtime_entity_key   TEXT NOT NULL UNIQUE,
  owner_deck_id        TEXT NOT NULL,
  deck_ids_json        TEXT NOT NULL,
  species_ids_json     TEXT NOT NULL,
  rank                 TEXT NOT NULL,
  scientific_name      TEXT NOT NULL,
  common_names_state   TEXT NOT NULL DEFAULT 'pending',
  attempt_count        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at      INTEGER,
  last_error           TEXT,
  last_failure_kind    TEXT,
  updated_at           INTEGER NOT NULL
)
''';

/// Already-shrunk (v14) shape — used to verify the v13 -> v14 migration is a
/// harmless no-op when a fresh/very-old install jumps straight to v14 with
/// nothing left to rename-recreate-copy.
const _v14EnrichmentTaxonomyWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key             TEXT PRIMARY KEY,
  runtime_entity_key   TEXT NOT NULL UNIQUE,
  deck_ids_json        TEXT NOT NULL,
  species_ids_json     TEXT NOT NULL,
  rank                 TEXT NOT NULL,
  scientific_name      TEXT NOT NULL,
  common_names_state   TEXT NOT NULL DEFAULT 'pending',
  updated_at           INTEGER NOT NULL
)
''';

/// Full v14 shape (after v11 -> v12 added the retry columns) — the source
/// shape the v14 -> v15 migration reads and slims.
const _v14FullEnrichmentTaxonomyWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key             TEXT PRIMARY KEY,
  runtime_entity_key   TEXT NOT NULL UNIQUE,
  deck_ids_json        TEXT NOT NULL,
  species_ids_json     TEXT NOT NULL,
  rank                 TEXT NOT NULL,
  scientific_name      TEXT NOT NULL,
  common_names_state   TEXT NOT NULL DEFAULT 'pending',
  attempt_count        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at      INTEGER,
  last_error           TEXT,
  last_failure_kind    TEXT,
  updated_at           INTEGER NOT NULL
)
''';

/// Already-slim (v15) shape — verifies the v14 -> v15 migration is a harmless
/// no-op (just creates the junction) when nothing needs backfilling/dropping.
const _v15EnrichmentTaxonomyWorkSql = '''
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key             TEXT PRIMARY KEY,
  runtime_entity_key   TEXT NOT NULL UNIQUE,
  common_names_state   TEXT NOT NULL DEFAULT 'pending',
  attempt_count        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at      INTEGER,
  last_error           TEXT,
  last_failure_kind    TEXT,
  updated_at           INTEGER NOT NULL
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

      await migrateUserDbToV6(db);

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

  test('migrating v6 -> v7 adds review_mode with a flip default, preserving '
      'existing rows', () async {
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

    await migrateUserDbToV7(db);

    final rows = await db.query('deck_config');
    expect(rows, hasLength(1));
    expect(rows.single['deck_id'], 'deck-1');
    expect(rows.single['desired_retention'], 0.85);
    expect(rows.single['learning_mode'], 'family');
    expect(rows.single['review_mode'], 'flip');
  });

  test(
    'migrating v7 -> v8 adds sortOrder to decks, backfilled by creation order',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 7);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.insert('decks', {'id': 'deck-1', 'name': 'First'});
      await db.insert('decks', {'id': 'deck-2', 'name': 'Second'});
      await db.insert('decks', {'id': 'deck-3', 'name': 'Third'});

      await migrateUserDbToV8(db);

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

      await migrateUserDbToV9(db);

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

  test('migrating v9 -> v10 adds sourceId and updatedAt to decks, nullable for '
      'existing rows', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 9);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.insert('decks', {'id': 'deck-1', 'name': 'Existing Deck'});

    await migrateUserDbToV10(db);

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
  });

  test('migrating v10 -> v11 drops the daily new-card/review limits, preserving '
      'the remaining deck_config columns', () async {
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

    await migrateUserDbToV11(db);

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
  });

  test('v11 -> v12 step 1 (seed) is additive: old enrichment_species_work columns '
      'survive, and the new capability/membership/unresolved-names tables are '
      'backfilled from existing data', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 11);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v11EnrichmentJobsSql);
    await db.execute(_v11EnrichmentSpeciesWorkSql);

    await db.insert('decks', {'id': 'deck-a', 'name': 'Deck A'});
    await db.insert('decks', {'id': 'deck-b', 'name': 'Deck B'});
    await db.insert('decks', {'id': 'deck-c', 'name': 'Deck C'});

    // deck-a wants iNat enrichment and still has one genuinely unresolved
    // name; deck-b does not want iNat enrichment at all but shares
    // species-1 with deck-a.
    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-a',
      'status': 'completed',
      'payload_json': jsonEncode({
        'includeINatPhotos': true,
        'includeCommonNames': true,
        'unresolvedSpeciesNames': ['Unknownus fishus'],
        'stillUnresolvedNames': <String>[],
      }),
      'updated_at': 1000,
    });
    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-b',
      'status': 'completed',
      'payload_json': jsonEncode({
        'includeINatPhotos': false,
        'includeCommonNames': false,
        'unresolvedSpeciesNames': <String>[],
        'stillUnresolvedNames': <String>[],
      }),
      'updated_at': 1000,
    });
    // deck-c already attempted name resolution: 'Resolved species' was
    // resolved (dropped from stillUnresolvedNames), 'Stubborn species'
    // was not — only the latter should survive into the new table.
    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-c',
      'status': 'completed',
      'payload_json': jsonEncode({
        'includeINatPhotos': true,
        'includeCommonNames': true,
        'unresolvedSpeciesNames': ['Resolved species', 'Stubborn species'],
        'stillUnresolvedNames': ['Stubborn species'],
      }),
      'updated_at': 1000,
    });

    await db.insert('enrichment_species_work', {
      'species_id': 'species-1',
      'owner_deck_id': 'deck-a',
      'deck_ids_json': jsonEncode(['deck-a', 'deck-b']),
      'deck_count': 2,
      'base_state': 'succeeded',
      'inat_primary_state': 'pending',
      'species_common_names_state': 'pending',
      'inat_backfill_state': 'pending',
      'updated_at': 2000,
    });

    await v12SeedQueueTables(db);

    // Old columns/table are untouched — EnrichmentJobExecutor keeps working.
    final speciesWorkRows = await db.query('enrichment_species_work');
    expect(speciesWorkRows, hasLength(1));
    final speciesWork = speciesWorkRows.single;
    expect(speciesWork['base_state'], 'succeeded');
    expect(speciesWork['inat_primary_state'], 'pending');
    expect(speciesWork['deck_ids_json'], jsonEncode(['deck-a', 'deck-b']));

    // OR'd-across-decks consent: deck-a wants iNat, deck-b doesn't, so the
    // shared species should still get enrichment.
    expect(speciesWork['wants_inat_photos'], 1);
    expect(speciesWork['wants_common_names'], 1);

    // Membership junction rows for both decks referencing species-1.
    final membershipRows = await db.query(
      'enrichment_species_deck_membership',
      orderBy: 'deck_id',
    );
    expect(membershipRows.map((r) => r['deck_id']), ['deck-a', 'deck-b']);
    expect(membershipRows.every((r) => r['species_id'] == 'species-1'), isTrue);

    // Per-capability queue rows: base succeeded -> done, the rest pending.
    final capabilityRows = await db.query(
      'enrichment_species_capability_state',
      orderBy: 'priority_tier',
    );
    expect(capabilityRows, hasLength(4));
    final byCapability = {
      for (final row in capabilityRows) row['capability'] as String: row,
    };
    expect(byCapability['base']!['state'], 'done');
    expect(byCapability['base']!['priority_tier'], 0);
    expect(byCapability['inatPrimary']!['state'], 'pending');
    expect(byCapability['inatPrimary']!['priority_tier'], 10);
    expect(byCapability['speciesCommonNames']!['state'], 'pending');
    expect(byCapability['speciesCommonNames']!['priority_tier'], 20);
    expect(byCapability['inatBackfill']!['state'], 'pending');
    expect(byCapability['inatBackfill']!['priority_tier'], 40);

    // Unresolved names: deck-a's untouched list carries over; deck-c only
    // keeps the name that stillUnresolvedNames says is still outstanding.
    final unresolvedRows = await db.query(
      'enrichment_unresolved_names',
      orderBy: 'deck_id',
    );
    expect(unresolvedRows.map((r) => (r['deck_id'], r['name'])), [
      ('deck-a', 'Unknownus fishus'),
      ('deck-c', 'Stubborn species'),
    ]);
    expect(unresolvedRows.every((r) => r['state'] == 'pending'), isTrue);
  });

  test('v11 -> v12 step 1 (seed) on a fresh/very-old install (no prior enrichment '
      'tables) creates the new tables empty without failing', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 11);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    // Deliberately do not create any enrichment_* tables, simulating an
    // install old enough to have never reached the version that first
    // created them (those are normally only created by the trailing
    // _createCurrentUserSchema safety net).

    await v12SeedQueueTables(db);

    expect(await db.query('enrichment_species_work'), isEmpty);
    expect(await db.query('enrichment_species_capability_state'), isEmpty);
    expect(await db.query('enrichment_species_deck_membership'), isEmpty);
    expect(await db.query('enrichment_unresolved_names'), isEmpty);
  });

  test('v11 -> v12 step 2 (cutover) shrinks enrichment_species_work, deletes '
      'non-cover job-stage rows, and shrinks payload_json to just '
      'coverImageUrl', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 12);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v11EnrichmentJobsSql);
    await db.execute(_v12EnrichmentSpeciesWorkSql);
    await db.execute(_v12EnrichmentJobStagesSql);

    await db.insert('decks', {'id': 'deck-a', 'name': 'Deck A'});

    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-a',
      'status': 'completed',
      'payload_json': jsonEncode({
        'coverImageUrl': 'https://example.com/cover.jpg',
        'speciesIds': ['species-1'],
        'includeINatPhotos': true,
        'includeCommonNames': true,
      }),
      'updated_at': 1000,
    });

    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-a',
      'stage': 'cover',
      'state': 'succeeded',
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-a',
      'stage': 'base',
      'state': 'succeeded',
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-a',
      'stage': 'inatPrimary',
      'state': 'pending',
    });

    await db.insert('enrichment_species_work', {
      'species_id': 'species-1',
      'owner_deck_id': 'deck-a',
      'deck_ids_json': jsonEncode(['deck-a']),
      'deck_count': 1,
      'base_state': 'succeeded',
      'inat_primary_state': 'pending',
      'species_common_names_state': 'pending',
      'inat_backfill_state': 'pending',
      'wants_inat_photos': 1,
      'wants_common_names': 1,
      'updated_at': 2000,
    });

    await v12CutoverSpeciesWorkAndJobs(db);

    final speciesWorkRows = await db.query('enrichment_species_work');
    expect(speciesWorkRows, hasLength(1));
    final speciesWork = speciesWorkRows.single;
    expect(speciesWork['species_id'], 'species-1');
    expect(speciesWork['owner_deck_id'], 'deck-a');
    expect(speciesWork['deck_count'], 1);
    expect(speciesWork['wants_inat_photos'], 1);
    expect(speciesWork['wants_common_names'], 1);
    expect(speciesWork.containsKey('base_state'), isFalse);
    expect(speciesWork.containsKey('deck_ids_json'), isFalse);

    final stageRows = await db.query('enrichment_job_stages');
    expect(stageRows, hasLength(1));
    expect(stageRows.single['stage'], 'cover');

    final jobRows = await db.query('enrichment_jobs');
    final payload =
        jsonDecode(jobRows.single['payload_json'] as String)
            as Map<String, dynamic>;
    expect(payload, {'coverImageUrl': 'https://example.com/cover.jpg'});
  });

  test('v11 -> v12 step 2 (cutover) discards enrichment_jobs rows left by the old '
      'executor in a non-terminal status, but keeps terminal ones', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 12);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v11EnrichmentJobsSql);
    await db.execute(_v12EnrichmentJobStagesSql);

    await db.insert('decks', {'id': 'deck-done', 'name': 'Deck Done'});
    await db.insert('decks', {'id': 'deck-stuck', 'name': 'Deck Stuck'});
    await db.insert('decks', {
      'id': 'deck-never-reached-cover',
      'name': 'Deck Never Reached Cover',
    });

    // Already finished before the upgrade: kept as-is.
    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-done',
      'status': 'completed',
      'payload_json': jsonEncode({'coverImageUrl': null}),
      'updated_at': 1000,
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-done',
      'stage': 'cover',
      'state': 'succeeded',
    });

    // Old executor: cover already succeeded, then interrupted mid-`inatPrimary`
    // — the common case, since `cover` ran early in the old stage order.
    // Without cleanup this would be unreclaimable forever (no pending/running
    // stage row survives the cutover) and would freeze `coverTerminal` false.
    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-stuck',
      'status': 'runningForeground',
      'payload_json': jsonEncode({
        'coverImageUrl': 'https://example.com/cover.jpg',
      }),
      'lease_owner': 'old-owner',
      'lease_expires_at': 500,
      'updated_at': 1000,
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-stuck',
      'stage': 'cover',
      'state': 'succeeded',
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-stuck',
      'stage': 'inatPrimary',
      'state': 'running',
    });

    // Interrupted before ever reaching the old `cover` stage: no cover row
    // at all, status stuck at `queued`.
    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-never-reached-cover',
      'status': 'queued',
      'payload_json': jsonEncode({
        'coverImageUrl': 'https://example.com/cover2.jpg',
      }),
      'updated_at': 1000,
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-never-reached-cover',
      'stage': 'nameResolution',
      'state': 'succeeded',
    });

    await v12CutoverSpeciesWorkAndJobs(db);

    final remainingJobDeckIds = (await db.query(
      'enrichment_jobs',
      columns: ['deck_id'],
    )).map((row) => row['deck_id']);
    expect(remainingJobDeckIds, ['deck-done']);

    final remainingStageDeckIds = (await db.query(
      'enrichment_job_stages',
      columns: ['deck_id'],
    )).map((row) => row['deck_id']);
    expect(remainingStageDeckIds, ['deck-done']);
  });

  test('v11 -> v12 step 2 (cutover) is a no-op when enrichment_species_work is '
      'already in the shrunk shape', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 12);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v13EnrichmentSpeciesWorkSql);

    await v12CutoverSpeciesWorkAndJobs(db);

    expect(await db.query('enrichment_species_work'), isEmpty);
  });

  test('v11 -> v12 step 3 (drop taxonomy owner) drops owner_deck_id from enrichment_taxonomy_work '
      'while preserving deck_ids_json/species_ids_json', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 13);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v13EnrichmentTaxonomyWorkSql);

    await db.insert('enrichment_taxonomy_work', {
      'work_key': 'genus:taxon:1',
      'runtime_entity_key': 'genus:acropora',
      'owner_deck_id': 'deck-1',
      'deck_ids_json': jsonEncode(['deck-1', 'deck-2']),
      'species_ids_json': jsonEncode(['sp-a', 'sp-b']),
      'rank': 'genus',
      'scientific_name': 'Acropora',
      'common_names_state': 'done',
      'updated_at': 1000,
    });

    await v12DropTaxonomyOwnerDeckId(db);

    final rows = await db.query('enrichment_taxonomy_work');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.containsKey('owner_deck_id'), isFalse);
    expect(row['work_key'], 'genus:taxon:1');
    expect(row['runtime_entity_key'], 'genus:acropora');
    expect(
      (jsonDecode(row['deck_ids_json']! as String) as List<dynamic>)
          .cast<String>(),
      ['deck-1', 'deck-2'],
    );
    expect(
      (jsonDecode(row['species_ids_json']! as String) as List<dynamic>)
          .cast<String>(),
      ['sp-a', 'sp-b'],
    );
    expect(row['common_names_state'], 'done');
  });

  test('v11 -> v12 step 3 (drop taxonomy owner) is a no-op when enrichment_taxonomy_work is '
      'already in the shrunk shape', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 13);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v14EnrichmentTaxonomyWorkSql);

    await v12DropTaxonomyOwnerDeckId(db);

    expect(await db.query('enrichment_taxonomy_work'), isEmpty);
  });

  test('v11 -> v12 step 4 (normalize taxonomy) moves species membership into the junction and '
      'drops deck_ids_json/species_ids_json/rank/scientific_name', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 14);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v14FullEnrichmentTaxonomyWorkSql);
    await db.execute(
      'CREATE INDEX idx_enrichment_taxonomy_work_runtime_entity '
      'ON enrichment_taxonomy_work(runtime_entity_key)',
    );

    await db.insert('enrichment_taxonomy_work', {
      'work_key': 'genus:taxon:1',
      'runtime_entity_key': 'genus:acropora',
      'deck_ids_json': jsonEncode(['deck-1', 'deck-2']),
      'species_ids_json': jsonEncode(['sp-a', 'sp-b']),
      'rank': 'genus',
      'scientific_name': 'Acropora',
      'common_names_state': 'done',
      'attempt_count': 2,
      'next_attempt_at': 5000,
      'last_error': 'boom',
      'last_failure_kind': 'temporary',
      'updated_at': 1000,
    });

    await v12NormalizeTaxonomySpecies(db);

    final rows = await db.query('enrichment_taxonomy_work');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.containsKey('deck_ids_json'), isFalse);
    expect(row.containsKey('species_ids_json'), isFalse);
    expect(row.containsKey('rank'), isFalse);
    expect(row.containsKey('scientific_name'), isFalse);
    expect(row['work_key'], 'genus:taxon:1');
    expect(row['runtime_entity_key'], 'genus:acropora');
    expect(row['common_names_state'], 'done');
    expect(row['attempt_count'], 2);
    expect(row['next_attempt_at'], 5000);
    expect(row['last_error'], 'boom');
    expect(row['last_failure_kind'], 'temporary');
    expect(row['updated_at'], 1000);

    final speciesRows = await db.query(
      'enrichment_taxonomy_work_species',
      orderBy: 'species_id ASC',
    );
    expect(
      speciesRows.map((r) => [r['work_key'], r['species_id']]),
      [
        ['genus:taxon:1', 'sp-a'],
        ['genus:taxon:1', 'sp-b'],
      ],
    );

    // The runtime-entity index survives the rename-recreate (DROP INDEX frees
    // its name so the recreate doesn't silently no-op).
    final indexRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = 'idx_enrichment_taxonomy_work_runtime_entity'",
    );
    expect(indexRows, hasLength(1));
  });

  test('v11 -> v12 step 4 (normalize taxonomy) just creates the junction when '
      'enrichment_taxonomy_work is already slim', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 14);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v15EnrichmentTaxonomyWorkSql);

    await v12NormalizeTaxonomySpecies(db);

    expect(await db.query('enrichment_taxonomy_work'), isEmpty);
    expect(await db.query('enrichment_taxonomy_work_species'), isEmpty);
  });

  test('v11 -> v12 end to end: a real v11 database reaches the final schema in '
      'a single migration (capability/membership backfilled, old columns '
      'dropped, taxonomy normalized)', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 11);
    addTearDown(db.close);

    Future<bool> hasColumn(String table, String col) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      return info.any((r) => r['name'] == col);
    }

    await db.execute(_legacyDecksSql);
    await db.execute(_v11EnrichmentJobsSql);
    await db.execute(_v12EnrichmentJobStagesSql);
    await db.execute(_v11EnrichmentSpeciesWorkSql);
    await db.execute(_v11EnrichmentTaxonomyWorkSql);

    await db.insert('enrichment_jobs', {
      'deck_id': 'deck-1',
      // Terminal status so step 2's stale-job pruning keeps it (and its cover
      // stage); a non-terminal job would be discarded along with its stages.
      'status': 'completed',
      'payload_json': jsonEncode({
        'includeINatPhotos': true,
        'includeCommonNames': false,
        'coverImageUrl': 'https://example.org/cover.jpg',
      }),
      'updated_at': 1000,
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-1',
      'stage': 'cover',
      'state': 'pending',
    });
    await db.insert('enrichment_job_stages', {
      'deck_id': 'deck-1',
      'stage': 'base',
      'state': 'pending',
    });
    await db.insert('enrichment_species_work', {
      'species_id': 'sp-a',
      'owner_deck_id': 'deck-1',
      'deck_ids_json': jsonEncode(['deck-1']),
      'deck_count': 1,
      'base_state': 'succeeded',
      'inat_primary_state': 'pending',
      'species_common_names_state': 'pending',
      'inat_backfill_state': 'pending',
      'updated_at': 1000,
    });
    await db.insert('enrichment_taxonomy_work', {
      'work_key': 'genus:acropora',
      'runtime_entity_key': 'genus:acropora',
      'owner_deck_id': 'deck-1',
      'deck_ids_json': jsonEncode(['deck-1']),
      'species_ids_json': jsonEncode(['sp-a']),
      'rank': 'genus',
      'scientific_name': 'Acropora',
      'common_names_state': 'pending',
      'updated_at': 1000,
    });

    await migrateUserDbToV12(db);

    // Step 1 — capability + membership backfilled from the old state columns.
    final capabilities = await db.query(
      'enrichment_species_capability_state',
      where: 'species_id = ?',
      whereArgs: ['sp-a'],
      orderBy: 'priority_tier ASC',
    );
    expect(
      capabilities.map((r) => [r['capability'], r['state']]),
      [
        ['base', 'done'], // 'succeeded' -> 'done'
        ['inatPrimary', 'pending'],
        ['speciesCommonNames', 'pending'],
        ['inatBackfill', 'pending'],
      ],
    );
    final membership = await db.query('enrichment_species_deck_membership');
    expect(membership.map((r) => [r['species_id'], r['deck_id']]), [
      ['sp-a', 'deck-1'],
    ]);

    // Step 2 — species_work slimmed and only the cover stage survives.
    expect(await hasColumn('enrichment_species_work', 'base_state'), isFalse);
    final stages = await db.query('enrichment_job_stages');
    expect(stages.map((r) => r['stage']), ['cover']);

    // Steps 3 + 4 — taxonomy slimmed, species moved into the junction.
    for (final col in [
      'owner_deck_id',
      'deck_ids_json',
      'species_ids_json',
      'rank',
      'scientific_name',
    ]) {
      expect(
        await hasColumn('enrichment_taxonomy_work', col),
        isFalse,
        reason: '$col should be dropped',
      );
    }
    final taxonomySpecies = await db.query('enrichment_taxonomy_work_species');
    expect(taxonomySpecies.map((r) => [r['work_key'], r['species_id']]), [
      ['genus:acropora', 'sp-a'],
    ]);
  });

  test(
    'migrating v12 -> v13 prunes deck_config/flashcard_stats rows left '
    'behind by a deck deleted before FK enforcement existed, keeping rows '
    'for decks that still exist',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 12);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.execute(_currentDeckConfigSql);
      await db.execute(_currentFlashcardStatsSql);

      await db.insert('decks', {'id': 'deck-1', 'name': 'Still here'});
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.85,
      });
      await db.insert('flashcard_stats', {
        'species_id': 'species-1',
        'deck_id': 'deck-1',
      });

      // Orphaned rows referencing a deck that was deleted while cascade
      // cleanup never actually fired (FK enforcement was off).
      await db.insert('deck_config', {
        'deck_id': 'deck-gone',
        'desired_retention': 0.7,
      });
      await db.insert('flashcard_stats', {
        'species_id': 'species-2',
        'deck_id': 'deck-gone',
      });

      await migrateUserDbToV13(db);

      final deckConfigRows = await db.query('deck_config');
      expect(deckConfigRows.map((r) => r['deck_id']), ['deck-1']);

      final flashcardStatRows = await db.query('flashcard_stats');
      expect(flashcardStatRows.map((r) => r['deck_id']), ['deck-1']);
    },
  );

  test(
    'once FK enforcement is on, deleting a deck cascades to its '
    'deck_config/flashcard_stats rows',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 12);
      addTearDown(db.close);

      await db.execute(_legacyDecksSql);
      await db.execute(_currentDeckConfigSql);
      await db.execute(_currentFlashcardStatsSql);
      // Mirrors DatabaseHelper.userDb's onOpen, applied after migrations run.
      await db.execute('PRAGMA foreign_keys = ON');

      await db.insert('decks', {'id': 'deck-1', 'name': 'Test Deck'});
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.85,
      });
      await db.insert('flashcard_stats', {
        'species_id': 'species-1',
        'deck_id': 'deck-1',
      });

      await db.delete('decks', where: 'id = ?', whereArgs: ['deck-1']);

      expect(await db.query('deck_config'), isEmpty);
      expect(await db.query('flashcard_stats'), isEmpty);
    },
  );

  test(
    'migrating v15 -> v16 remaps legacy succeeded taxonomy rows to done, '
    'leaving every other state untouched',
    () async {
      final db = await openDatabase(inMemoryDatabasePath, version: 15);
      addTearDown(db.close);

      await db.execute(_v15EnrichmentTaxonomyWorkSql);

      await db.insert('enrichment_taxonomy_work', {
        'work_key': 'genus:acropora',
        'runtime_entity_key': 'genus:acropora',
        'common_names_state': 'succeeded',
        'attempt_count': 0,
        'updated_at': 1000,
      });
      await db.insert('enrichment_taxonomy_work', {
        'work_key': 'genus:favia',
        'runtime_entity_key': 'genus:favia',
        'common_names_state': 'done',
        'attempt_count': 0,
        'updated_at': 1000,
      });
      await db.insert('enrichment_taxonomy_work', {
        'work_key': 'genus:porites',
        'runtime_entity_key': 'genus:porites',
        'common_names_state': 'pending',
        'attempt_count': 0,
        'updated_at': 1000,
      });

      await migrateUserDbToV16(db);

      final rows = await db.query(
        'enrichment_taxonomy_work',
        orderBy: 'work_key',
      );
      final statesByWorkKey = {
        for (final row in rows) row['work_key'] as String: row['common_names_state'],
      };
      expect(statesByWorkKey, {
        'genus:acropora': 'done',
        'genus:favia': 'done',
        'genus:porites': 'pending',
      });
    },
  );
}
