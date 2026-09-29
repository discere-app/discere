import 'dart:io';

import 'package:discere/shared/persistence/schema/schema_asset.dart';
import 'package:discere/shared/persistence/schema/schema_reconciler.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/in_memory_user_database.dart';
import '../../../support/schema_snapshot.dart';

/// Reads the real assets from disk rather than through `rootBundle`: these
/// tests run on the host, and the point is to reconcile against exactly the
/// files that ship.
Future<List<SchemaAsset>> _loadShippedAssets() async {
  final assets = <SchemaAsset>[];
  for (final path in UserDbSchema.schemaAssetPaths) {
    assets.add(SchemaAsset.parse(await File(path).readAsString()));
  }
  return assets;
}

void main() {
  // openInMemoryUserDatabase runs UserDbSchema.create, which reads the
  // assets through rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SchemaReconciler against the shipped assets', () {
    late List<SchemaAsset> assets;

    setUp(() async {
      assets = await _loadShippedAssets();
    });

    /// The baseline every other case is compared against: what a fresh install
    /// looks like.
    Future<Map<String, Object?>> freshSnapshot() async {
      final db = await openInMemoryUserDatabase();
      addTearDown(db.close);
      return schemaSnapshot(db);
    }

    Future<Database> openBlank() async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await seedFtsTableForTestHost(db);
      return db;
    }

    test('builds the whole schema on an empty database', () async {
      final db = await openBlank();

      await SchemaReconciler.reconcile(db, assets);

      expect(await schemaSnapshot(db), await freshSnapshot());
    });

    test('is idempotent — a second run changes nothing', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      final afterFirst = await schemaSnapshot(db);

      await SchemaReconciler.reconcile(db, assets);

      expect(await schemaSnapshot(db), afterFirst);
    });

    test('recreates a table that went missing', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      await db.execute('DROP TABLE species_photo_gap_ack');

      await SchemaReconciler.reconcile(db, assets);

      expect(await schemaSnapshot(db), await freshSnapshot());
    });

    /// The case a hand-maintained repair list exists for, and the one it keeps
    /// missing: a column added to an asset that no migration ever adds.
    test('adds a column an existing table is missing', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      // Rebuild deck_config without review_mode, as a database that never ran
      // the migration adding it would have.
      await db.execute('ALTER TABLE deck_config RENAME TO deck_config_old');
      await db.execute('''
        CREATE TABLE deck_config (
          deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
          desired_retention    REAL    DEFAULT 0.9,
          maximum_interval     INTEGER DEFAULT 36500,
          learning_steps       TEXT    DEFAULT '1,10',
          relearning_steps     TEXT    DEFAULT '10',
          learning_mode        TEXT    NOT NULL DEFAULT 'species',
          name_type            TEXT    NOT NULL DEFAULT 'commonName'
        )
      ''');
      await db.execute('DROP TABLE deck_config_old');

      await SchemaReconciler.reconcile(db, assets);

      final columns = await db.rawQuery('PRAGMA table_info(deck_config)');
      final reviewMode = columns.firstWhere((c) => c['name'] == 'review_mode');
      expect(reviewMode['type'], 'TEXT');
      expect(reviewMode['notnull'], 1);
      expect(reviewMode['dflt_value'], "'flip'");
    });

    test('keeps the rows in a table it widens', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      // deck_config as it was before review_mode existed, with a deck's
      // settings already in it.
      await db.execute('DROP TABLE deck_config');
      await db.execute('''
        CREATE TABLE deck_config (
          deck_id           TEXT PRIMARY KEY,
          desired_retention REAL DEFAULT 0.9
        )
      ''');
      await db.insert('deck_config', {
        'deck_id': 'deck-1',
        'desired_retention': 0.77,
      });

      await SchemaReconciler.reconcile(db, assets);

      final row = (await db.query('deck_config')).single;
      expect(row['deck_id'], 'deck-1');
      expect(row['desired_retention'], 0.77);
      // Widened structurally: the new columns arrive with the asset's
      // defaults, and nothing else about the row is touched.
      expect(row['review_mode'], 'flip');
      expect(row['learning_mode'], 'species');
      // Nullable and undefaulted, so it stays empty — reconciliation never
      // invents data.
      expect(row['learning_steps'], '1,10');
    });

    /// A column that cannot be added has to say so: skipping it silently
    /// leaves every query naming it failing later with nothing to point at.
    test('refuses a column it cannot add, naming it', () async {
      final db = await openBlank();
      await db.execute('CREATE TABLE gadgets (id TEXT PRIMARY KEY)');
      final widened = SchemaAsset.parse('''
CREATE TABLE IF NOT EXISTS gadgets (
  id    TEXT PRIMARY KEY,
  label TEXT NOT NULL
);
''');

      expect(
        () => SchemaReconciler.reconcile(db, [widened]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('gadgets'), contains('label'), contains('NOT NULL')),
          ),
        ),
      );
    });

    test('rebuilds an index that went missing', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      await db.execute('DROP INDEX idx_enrichment_jobs_status_updated');

      await SchemaReconciler.reconcile(db, assets);

      expect(await schemaSnapshot(db), await freshSnapshot());
    });

    /// Indexes come last for this reason: an index over a column the same run
    /// has just added cannot be built before it.
    test('builds an index over a column it added in the same run', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      await db.execute('DROP TABLE enrichment_jobs');
      // enrichment_jobs as it was before cover_state and its index existed.
      await db.execute('''
        CREATE TABLE enrichment_jobs (
          deck_id     TEXT PRIMARY KEY,
          status      TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          updated_at  INTEGER NOT NULL
        )
      ''');

      await SchemaReconciler.reconcile(db, assets);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'enrichment_jobs'",
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_enrichment_jobs_cover_state'),
      );
    });

    /// The probe table is an implementation detail; leaving one behind would
    /// make the next run read its column list from a stale table.
    test('leaves no probe table behind', () async {
      final db = await openBlank();
      await SchemaReconciler.reconcile(db, assets);
      await SchemaReconciler.reconcile(db, assets);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name LIKE '%__schema_probe'",
      );
      expect(tables, isEmpty);
    });
  });
}
