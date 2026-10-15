import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/in_memory_user_database.dart';

// Two old-format IDs that the reference database merged into one entity,
// a third renamed on its own, and a species ID without any alias. `_aliasA`
// sorts before `_aliasB`, which the "smaller old ID" tie-break relies on.
const _aliasA = 'discere:fishbase_species:6509';
const _aliasB = 'discere:sealifebase_species:67018';
const _merged = 'discere:species:6002';
const _aliasC = 'discere:fishbase_species:898';
const _renamed = 'discere:species:834';
const _unaliased = 'discere:species:999';
const _genusAlias = 'discere:fishbase_genus:5120';
const _genus = 'discere:genus:5106';

const _installedVersion = 7;
final _ranAt = DateTime(2026, 10, 15, 9, 30);
const _watchlistKey = 'watchlist';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database userDb;
  late Database referenceDb;
  late SharedPreferences preferences;

  setUp(() async {
    userDb = await openInMemoryUserDatabase();
    referenceDb = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await referenceDb.execute(
      'CREATE TABLE entity_aliases (alias_id TEXT NOT NULL PRIMARY KEY, '
      'entity_id TEXT NOT NULL) WITHOUT ROWID',
    );
    for (final (alias, entity) in const [
      (_aliasA, _merged),
      (_aliasB, _merged),
      (_aliasC, _renamed),
      (_genusAlias, _genus),
    ]) {
      await referenceDb.insert('entity_aliases', {
        'alias_id': alias,
        'entity_id': entity,
      });
    }
    for (final deckId in const ['d1', 'd2']) {
      await userDb.insert('decks', {'id': deckId, 'name': deckId});
    }
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await userDb.close();
    await referenceDb.close();
  });

  Future<void> run({DateTime? at}) => ReferenceIdMigration(
    userDb: userDb,
    referenceDb: referenceDb,
    preferences: preferences,
    idListPreferenceKeys: const {_watchlistKey},
    now: () => at ?? _ranAt,
  ).applyIfNeeded(installedVersion: _installedVersion);

  ReferenceIdMigrationRun? lastRun() =>
      ReferenceIdMigrationRun.read(preferences);

  Future<List<Map<String, Object?>>> rows(String table, {String? orderBy}) =>
      userDb.query(table, orderBy: orderBy);

  Future<void> insertStat(
    String speciesId, {
    int? lastReview,
    int? nextReview,
    required double stability,
  }) => userDb.insert('flashcard_stats', {
    'species_id': speciesId,
    'deck_id': 'd1',
    'last_review_date': lastReview,
    'next_review_date': nextReview,
    'stability': stability,
  });

  Future<void> insertRuntimeName(
    String entityKey,
    String name, {
    int? placeId,
    required int fetchedAt,
  }) => userDb.insert('runtime_common_names', {
    'entity_key': entityKey,
    'entity_type': 'species',
    'language_code': 'en',
    'name': name,
    'place_id': placeId,
    'fetched_at': fetchedAt,
  });

  group('every table of the matrix', () {
    test('has its aliased IDs rewritten, and unaliased IDs and name keys '
        'left alone', () async {
      await insertStat(_aliasC, stability: 1);
      await insertStat(_unaliased, stability: 2);
      await userDb.insert('species_photo_gap_ack', {
        'deck_id': 'd1',
        'species_id': _aliasC,
        'acknowledged_at': 1,
      });
      await userDb.insert('enrichment_species_deck_membership', {
        'species_id': _aliasC,
        'deck_id': 'd1',
      });
      await userDb.insert('enrichment_species_work', {
        'species_id': _aliasC,
        'owner_deck_id': 'd1',
        'deck_count': 1,
        'updated_at': 1,
      });
      await userDb.insert('enrichment_species_capability_state', {
        'species_id': _aliasC,
        'capability': 'base',
        'updated_at': 1,
      });
      await userDb.insert('enrichment_taxonomy_work_species', {
        'work_key': 'genus:prionace',
        'species_id': _aliasC,
      });
      await userDb.insert('inat_photo_cache', {
        'species_id': _aliasC,
        'photo_url': 'https://example.org/1.jpg',
        'fetched_at': 1,
      });
      for (final entityId in const [_aliasC, 'genus:gobio']) {
        await userDb.insert('external_identifier_cache', {
          'entity_id': entityId,
          'provider': 'inaturalist',
          'external_id': '42',
          'last_synced_at': 1,
        });
      }
      await insertRuntimeName('species:$_aliasC', 'Blue shark', fetchedAt: 1);
      await insertRuntimeName('genus:gobio', 'Gudgeons', fetchedAt: 1);
      for (final (key, id) in const [
        ('species:$_aliasC', _aliasC),
        ('genus:gobio', _genusAlias),
      ]) {
        await userDb.insert('runtime_common_name_search_documents', {
          'entity_key': key,
          'entity_id': id,
          'entity_type': 'species',
          'scientific_name': 'x',
          'normalized_search_text': 'x',
        });
      }

      await run();

      expect(
        (await rows('flashcard_stats', orderBy: 'stability'))
            .map((r) => r['species_id']),
        [_renamed, _unaliased],
      );
      for (final table in const [
        'species_photo_gap_ack',
        'enrichment_species_deck_membership',
        'enrichment_species_work',
        'enrichment_species_capability_state',
        'enrichment_taxonomy_work_species',
        'inat_photo_cache',
      ]) {
        expect(
          (await rows(table)).single['species_id'],
          _renamed,
          reason: table,
        );
      }
      expect(
        (await rows('external_identifier_cache', orderBy: 'entity_id'))
            .map((r) => r['entity_id']),
        [_renamed, 'genus:gobio'],
      );
      expect(
        (await rows('runtime_common_names', orderBy: 'entity_key'))
            .map((r) => r['entity_key']),
        ['genus:gobio', 'species:$_renamed'],
      );
      expect(
        (await rows(
          'runtime_common_name_search_documents',
          orderBy: 'entity_key',
        )).map((r) => (r['entity_key'], r['entity_id'])),
        [('genus:gobio', _genus), ('species:$_renamed', _renamed)],
      );
    });
  });

  group('flashcard_stats keeps one card per collision', () {
    Future<double> survivingStability() async =>
        (await rows('flashcard_stats')).single['stability'] as double;

    test('the one reviewed last', () async {
      await insertStat(_aliasA, lastReview: 100, stability: 1);
      await insertStat(_aliasB, lastReview: 200, stability: 2);
      await run();
      expect(await survivingStability(), 2);
    });

    test('a review date before none', () async {
      await insertStat(_aliasA, stability: 1);
      await insertStat(_aliasB, lastReview: 100, stability: 2);
      await run();
      expect(await survivingStability(), 2);
    });

    test('with equal review dates, the one due last', () async {
      await insertStat(_aliasA, lastReview: 100, nextReview: 300, stability: 1);
      await insertStat(_aliasB, lastReview: 100, nextReview: 500, stability: 2);
      await run();
      expect(await survivingStability(), 2);
    });

    test('with equal review dates, a due date before none', () async {
      await insertStat(_aliasA, lastReview: 100, stability: 1);
      await insertStat(_aliasB, lastReview: 100, nextReview: 300, stability: 2);
      await run();
      expect(await survivingStability(), 2);
    });

    test('with equal dates, the one with the smaller old ID', () async {
      await insertStat(_aliasB, lastReview: 100, nextReview: 300, stability: 2);
      await insertStat(_aliasA, lastReview: 100, nextReview: 300, stability: 1);
      await run();
      expect(await survivingStability(), 1);
    });

    test('also against a card already under the valid ID', () async {
      await insertStat(_merged, lastReview: 100, stability: 1);
      await insertStat(_aliasA, lastReview: 200, stability: 2);
      await run();
      final survivor = (await rows('flashcard_stats')).single;
      expect(survivor['species_id'], _merged);
      expect(survivor['stability'], 2);
    });
  });

  test('runtime_common_names drops identical names, keeping the one fetched '
      'last, and tells a regional name from a global one', () async {
    await insertRuntimeName('species:$_merged', 'Clownfish', fetchedAt: 200);
    await insertRuntimeName('species:$_aliasA', 'Clownfish', fetchedAt: 300);
    await insertRuntimeName(
      'species:$_aliasB',
      'Clownfish',
      placeId: 1,
      fetchedAt: 100,
    );

    await run();

    expect(
      (await rows('runtime_common_names', orderBy: 'fetched_at')).map(
        (r) => (r['entity_key'], r['place_id'], r['fetched_at']),
      ),
      [('species:$_merged', 1, 100), ('species:$_merged', null, 300)],
    );
  });

  test('enrichment_species_work keeps the existing row, combines consent and '
      'recounts its decks', () async {
    await userDb.insert('enrichment_species_work', {
      'species_id': _merged,
      'owner_deck_id': 'd1',
      'deck_count': 1,
      'wants_inat_photos': 0,
      'wants_common_names': 1,
      'updated_at': 1,
    });
    await userDb.insert('enrichment_species_work', {
      'species_id': _aliasA,
      'owner_deck_id': 'd2',
      'deck_count': 1,
      'wants_inat_photos': 1,
      'wants_common_names': 0,
      'updated_at': 1,
    });
    for (final (species, deck) in const [(_merged, 'd1'), (_aliasA, 'd2')]) {
      await userDb.insert('enrichment_species_deck_membership', {
        'species_id': species,
        'deck_id': deck,
      });
    }

    await run();

    final work = (await rows('enrichment_species_work')).single;
    expect(work['species_id'], _merged);
    expect(work['owner_deck_id'], 'd1');
    expect(work['wants_inat_photos'], 1);
    expect(work['wants_common_names'], 1);
    expect(work['deck_count'], 2);
  });

  group('enrichment_species_capability_state keeps one row per collision', () {
    Future<void> insertCapability(
      String species,
      String capability, {
      String state = 'pending',
      int attempts = 0,
    }) => userDb.insert('enrichment_species_capability_state', {
      'species_id': species,
      'capability': capability,
      'state': state,
      'attempt_count': attempts,
      'updated_at': 1,
    });

    test('the one already under the valid ID, and rewrites the rest', () async {
      await insertCapability(_merged, 'base', attempts: 1);
      await insertCapability(_aliasA, 'base', attempts: 2);
      await insertCapability(_aliasA, 'inatPrimary');

      await run();

      expect(
        (await rows(
          'enrichment_species_capability_state',
          orderBy: 'capability',
        )).map((r) => (r['species_id'], r['capability'], r['attempt_count'])),
        [(_merged, 'base', 1), (_merged, 'inatPrimary', 0)],
      );
    });

    test('a completed one before the one under the valid ID', () async {
      await insertCapability(_merged, 'base', state: 'permanentFailure');
      await insertCapability(_aliasA, 'base', state: 'done');

      await run();

      expect(
        (await rows('enrichment_species_capability_state'))
            .map((r) => (r['species_id'], r['state'])),
        [(_merged, 'done')],
      );
    });
  });

  test('the duplicate-discarding tables keep the row already under the '
      'valid ID', () async {
    for (final species in const [_merged, _aliasA]) {
      await userDb.insert('enrichment_species_deck_membership', {
        'species_id': species,
        'deck_id': 'd1',
      });
      await userDb.insert('enrichment_taxonomy_work_species', {
        'work_key': 'genus:amphiprion',
        'species_id': species,
      });
      await userDb.insert('species_photo_gap_ack', {
        'deck_id': 'd1',
        'species_id': species,
        'acknowledged_at': species == _merged ? 1 : 2,
      });
      await userDb.insert('inat_photo_cache', {
        'species_id': species,
        'photo_url': 'https://example.org/1.jpg',
        'fetched_at': species == _merged ? 1 : 2,
      });
      await userDb.insert('external_identifier_cache', {
        'entity_id': species,
        'provider': 'inaturalist',
        'external_id': species == _merged ? 'kept' : 'dropped',
        'last_synced_at': 1,
      });
    }

    await run();

    expect((await rows('enrichment_species_deck_membership')), hasLength(1));
    expect((await rows('enrichment_taxonomy_work_species')), hasLength(1));
    expect(
      (await rows('species_photo_gap_ack')).single['acknowledged_at'],
      1,
    );
    expect((await rows('inat_photo_cache')).single['fetched_at'], 1);
    expect(
      (await rows('external_identifier_cache')).single['external_id'],
      'kept',
    );
  });

  test('runtime_common_name_search_documents are merged into one document, '
      'and the full-text index follows', () async {
    for (final (key, names, text) in const [
      (
        'species:$_merged',
        'Clown anemonefish;Clownfish',
        'clown anemonefish clownfish',
      ),
      ('species:$_aliasA', 'Clownfish;Anemonefish', 'clownfish anemonefish'),
    ]) {
      final rowId = await userDb.insert(
        'runtime_common_name_search_documents',
        {
          'entity_key': key,
          'entity_id': key.substring('species:'.length),
          'entity_type': 'species',
          'scientific_name': 'Amphiprion ocellaris',
          'common_name_en': names,
          'normalized_search_text': text,
        },
      );
      await userDb.insert('runtime_common_name_search_fts', {
        'rowid': rowId,
        'scientific_name': 'Amphiprion ocellaris',
        'common_name_en': names,
      });
    }

    await run();

    final document =
        (await rows('runtime_common_name_search_documents')).single;
    expect(document['entity_key'], 'species:$_merged');
    expect(document['entity_id'], _merged);
    expect(
      document['common_name_en'],
      'Clown anemonefish;Clownfish;Anemonefish',
    );
    expect(
      document['normalized_search_text'],
      'clown anemonefish clownfish clownfish anemonefish',
    );
    final indexed = await userDb.rawQuery(
      'SELECT rowid, common_name_en FROM runtime_common_name_search_fts',
    );
    expect(indexed.single['common_name_en'], document['common_name_en']);
  });

  test('the watchlist in preferences is rewritten without duplicates',
      () async {
    await preferences.setStringList(_watchlistKey, [
      _aliasA,
      _unaliased,
      _aliasB,
    ]);

    await run();

    expect(preferences.getStringList(_watchlistKey), [_merged, _unaliased]);
  });

  test('a second run changes nothing', () async {
    await insertStat(_aliasA, lastReview: 100, stability: 1);
    await insertStat(_aliasB, lastReview: 200, stability: 2);
    await insertRuntimeName('species:$_aliasA', 'Clownfish', fetchedAt: 1);
    await preferences.setStringList(_watchlistKey, [_aliasA]);
    await run();
    final stats = await rows('flashcard_stats');
    final names = await rows('runtime_common_names');

    // Forget that it ran, so the second run does not just skip.
    await preferences.remove(ReferenceIdMigration.prefKeyAppliedVersion);
    final report = await ReferenceIdMigration(
      userDb: userDb,
      referenceDb: referenceDb,
      preferences: preferences,
      idListPreferenceKeys: const {_watchlistKey},
    ).applyIfNeeded(installedVersion: _installedVersion);

    expect(report!.counts, isEmpty);
    expect(await rows('flashcard_stats'), stats);
    expect(await rows('runtime_common_names'), names);
    expect(preferences.getStringList(_watchlistKey), [_merged]);
  });

  test('a failure part-way rolls every table back and is not recorded as '
      'applied', () async {
    await insertStat(_aliasC, stability: 1);
    await userDb.insert('inat_photo_cache', {
      'species_id': _aliasC,
      'photo_url': 'https://example.org/1.jpg',
      'fetched_at': 1,
    });
    // inat_photo_cache is rewritten well after flashcard_stats.
    await userDb.execute(
      'CREATE TRIGGER fail_photo_cache BEFORE UPDATE ON inat_photo_cache '
      "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );

    await expectLater(run(), throwsA(isA<DatabaseException>()));

    expect((await rows('flashcard_stats')).single['species_id'], _aliasC);
    expect(
      preferences.getInt(ReferenceIdMigration.prefKeyAppliedVersion),
      isNull,
    );
  });

  test('a schema-1 reference database, which has no aliases, rewrites '
      'nothing and is recorded as applied', () async {
    await referenceDb.execute('DROP TABLE entity_aliases');
    await insertStat(_aliasC, stability: 1);

    await run();

    expect((await rows('flashcard_stats')).single['species_id'], _aliasC);
    expect(
      preferences.getInt(ReferenceIdMigration.prefKeyAppliedVersion),
      _installedVersion,
    );
  });

  group('the recorded version', () {
    setUp(() => insertStat(_aliasC, stability: 1));

    test('skips the run when it is the installed one', () async {
      await preferences.setInt(
        ReferenceIdMigration.prefKeyAppliedVersion,
        _installedVersion,
      );
      await run();
      expect((await rows('flashcard_stats')).single['species_id'], _aliasC);
    });

    test('lets it run when it is another one, and becomes the installed '
        'one', () async {
      await preferences.setInt(
        ReferenceIdMigration.prefKeyAppliedVersion,
        _installedVersion - 1,
      );
      await run();
      expect((await rows('flashcard_stats')).single['species_id'], _renamed);
      expect(
        preferences.getInt(ReferenceIdMigration.prefKeyAppliedVersion),
        _installedVersion,
      );
    });
  });

  group('the recorded run', () {
    test('of a success holds what was referenced, aliased, rewritten and '
        'dropped', () async {
      // _aliasA and _aliasB collide: one card survives, one is dropped.
      await insertStat(_aliasA, lastReview: 100, stability: 1);
      await insertStat(_aliasB, lastReview: 200, stability: 2);
      await insertStat(_unaliased, stability: 3);
      await preferences.setStringList(_watchlistKey, [_aliasC]);

      await run();

      final recorded = lastRun();
      expect(recorded, isA<ReferenceIdMigrationSucceeded>());
      recorded as ReferenceIdMigrationSucceeded;
      expect(recorded.referenceDbVersion, _installedVersion);
      expect(recorded.ranAt, _ranAt);
      expect(recorded.referencedIdCount, 4);
      expect(recorded.aliasCount, 3);
      expect(recorded.targets, {
        'flashcard_stats': (rewritten: 1, dropped: 1),
        'preference $_watchlistKey': (rewritten: 1, dropped: 0),
      });
      expect(recorded.totalRewritten, 2);
      expect(recorded.totalDropped, 1);
    });

    test('of a run without aliases says nothing was rewritten', () async {
      await insertStat(_unaliased, stability: 1);

      await run();

      final recorded = lastRun();
      expect(recorded, isA<ReferenceIdMigrationSucceeded>());
      recorded as ReferenceIdMigrationSucceeded;
      expect(recorded.referencedIdCount, 1);
      expect(recorded.aliasCount, 0);
      expect(recorded.targets, isEmpty);
    });

    test('is not a success when the run fails', () async {
      await insertStat(_aliasC, stability: 1);
      await userDb.execute(
        'CREATE TRIGGER fail_stats BEFORE UPDATE ON flashcard_stats '
        "BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
      );

      await expectLater(run(), throwsA(isA<DatabaseException>()));

      expect(lastRun(), isNull);
    });

    test('is left alone by a later start at the same version', () async {
      await insertStat(_aliasC, stability: 1);
      await run();
      final recorded = preferences.getString(ReferenceIdMigrationRun.prefKey);
      expect(recorded, isNotNull);

      await run(at: _ranAt.add(const Duration(days: 1)));

      expect(
        preferences.getString(ReferenceIdMigrationRun.prefKey),
        recorded,
      );
    });
  });
}
