import 'dart:convert';

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

    await DatabaseHelper.migrateUserSchemaV6ToV7ForTesting(db);

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

  test('migrating v9 -> v10 adds sourceId and updatedAt to decks, nullable for '
      'existing rows', () async {
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
  });

  test('migrating v11 -> v12 is additive: old enrichment_species_work columns '
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

    await DatabaseHelper.migrateUserSchemaV11ToV12ForTesting(db);

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

  test('migrating v11 -> v12 on a fresh/very-old install (no prior enrichment '
      'tables) creates the new tables empty without failing', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 11);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    // Deliberately do not create any enrichment_* tables, simulating an
    // install old enough to have never reached the version that first
    // created them (those are normally only created by the trailing
    // _createCurrentUserSchema safety net).

    await DatabaseHelper.migrateUserSchemaV11ToV12ForTesting(db);

    expect(await db.query('enrichment_species_work'), isEmpty);
    expect(await db.query('enrichment_species_capability_state'), isEmpty);
    expect(await db.query('enrichment_species_deck_membership'), isEmpty);
    expect(await db.query('enrichment_unresolved_names'), isEmpty);
  });

  test('migrating v12 -> v13 shrinks enrichment_species_work, deletes '
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

    await DatabaseHelper.migrateUserSchemaV12ToV13ForTesting(db);

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

  test('migrating v12 -> v13 discards enrichment_jobs rows left by the old '
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

    await DatabaseHelper.migrateUserSchemaV12ToV13ForTesting(db);

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

  test('migrating v12 -> v13 is a no-op when enrichment_species_work is '
      'already in the shrunk shape', () async {
    final db = await openDatabase(inMemoryDatabasePath, version: 12);
    addTearDown(db.close);

    await db.execute(_legacyDecksSql);
    await db.execute(_v13EnrichmentSpeciesWorkSql);

    await DatabaseHelper.migrateUserSchemaV12ToV13ForTesting(db);

    expect(await db.query('enrichment_species_work'), isEmpty);
  });
}
