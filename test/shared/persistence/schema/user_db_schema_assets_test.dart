/// The invariants that make [SchemaReconciler] able to do its job at all.
///
/// Both are the kind of thing a written convention states and then quietly
/// stops being true about. They are tests so that the moment one breaks is the
/// moment someone edits an asset — not the moment a user's database is opened.
library;

import 'dart:io';

import 'package:discere/shared/persistence/schema/schema_asset.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where the user-database schema assets live.
const _assetDirectories = <String>[
  'assets/sql/user_db/tables',
  'assets/sql/user_db/fts',
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('every shipped schema asset is in UserDbSchema.schemaAssetPaths', () {
    final onDisk = <String>[];
    for (final directory in _assetDirectories) {
      final entries = Directory(directory).listSync();
      for (final entry in entries) {
        if (entry is! File || !entry.path.endsWith('.sql')) continue;
        onDisk.add(entry.path.replaceAll('\\', '/'));
      }
    }

    expect(
      onDisk,
      isNotEmpty,
      reason:
          'Found no schema assets at all — the directories moved and this '
          'test is now checking nothing.',
    );
    expect(
      onDisk.toSet(),
      UserDbSchema.schemaAssetPaths.toSet(),
      reason:
          'A schema asset on disk is missing from UserDbSchema.'
          'schemaAssetPaths (or the list names one that no longer exists). '
          'A table absent from that list is created by nothing and repaired '
          'by nothing.',
    );
  });

  test('every asset parses into exactly one table', () async {
    for (final path in UserDbSchema.schemaAssetPaths) {
      final asset = SchemaAsset.parse(await File(path).readAsString());
      expect(asset.tableName, isNotEmpty, reason: 'in $path');
    }
  });

  /// Not every column has to be addable: a table that exists at all was
  /// created with its original columns, so those never go missing. What must
  /// hold is that reconciliation either adds a column or says precisely why it
  /// cannot — see `schema_reconciler_test.dart`, which covers the diagnostic.
  ///
  /// Recorded here as the count it is, so that a change to the shipped assets
  /// that makes more columns un-addable is at least visible.
  test('the columns that cannot be added by ALTER are original ones', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    final notAddable = <String>[];
    for (final path in UserDbSchema.schemaAssetPaths) {
      final asset = SchemaAsset.parse(await File(path).readAsString());
      if (asset.isVirtual) continue;

      await db.execute(asset.createTable);
      final columns = await db.rawQuery(
        'PRAGMA table_info(${asset.tableName})',
      );
      for (final column in columns) {
        final notNull = (column['notnull'] as int? ?? 0) != 0;
        final hasDefault = column['dflt_value'] != null;
        final isPrimaryKey = (column['pk'] as int? ?? 0) != 0;
        if (isPrimaryKey || !notNull || hasDefault) continue;
        notAddable.add('${asset.tableName}.${column['name']}');
      }
    }

    // Each of these is reachable only on a table that already has it, so no
    // database is ever missing one. For most that is because the column has
    // been there since the table was created. `runtime_common_names.name` is
    // the exception and the reason this is worth stating: it replaced a
    // `names` column without a migration. No installation is known to
    // predate that change, but migration v19 drops the old shape regardless,
    // so the claim rests on code rather than on release history.
    //
    // A *new* column landing in this list is the thing to catch: it would
    // reach fresh installs and no existing database, and reconciliation would
    // raise rather than add it — which fails the database open, not just the
    // query.
    expect(
      notAddable,
      isNot(contains('deck_config.review_mode')),
      reason: 'sanity: a column with a default must never be listed here',
    );
    expect(
      notAddable.toSet(),
      {
        'decks.name',
        'species_photo_gap_ack.acknowledged_at',
        'inat_photo_cache.fetched_at',
        'runtime_common_names.entity_key',
        'runtime_common_names.entity_type',
        'runtime_common_names.language_code',
        'runtime_common_names.name',
        'runtime_common_names.fetched_at',
        'runtime_common_name_search_documents.entity_id',
        'runtime_common_name_search_documents.entity_type',
        'runtime_common_name_search_documents.scientific_name',
        'runtime_common_name_search_documents.normalized_search_text',
        'external_identifier_cache.external_id',
        'external_identifier_cache.last_synced_at',
        'enrichment_jobs.status',
        'enrichment_jobs.payload_json',
        'enrichment_jobs.updated_at',
        'enrichment_species_work.owner_deck_id',
        'enrichment_species_work.updated_at',
        'enrichment_taxonomy_work.runtime_entity_key',
        'enrichment_taxonomy_work.updated_at',
        'enrichment_species_capability_state.updated_at',
        'enrichment_unresolved_names.updated_at',
        'local_diagnostics_network_failures.created_at',
        'local_diagnostics_network_failures.host',
        'local_diagnostics_network_failures.method',
        'local_diagnostics_network_failures.url_path',
      },
      reason:
          'A column here cannot be added to a database that already has its '
          'table. If you just added one to an asset, give it a default or '
          'make it nullable — existing installs can never receive it '
          'otherwise. If you removed one, drop it from this list.',
    );
  });
}
