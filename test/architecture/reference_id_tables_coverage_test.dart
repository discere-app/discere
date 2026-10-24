/// Architecture test (ARCH-17) — every user-database column that can hold a
/// reference ID is rewritten by `ReferenceIdMigration`.
///
/// `referenceIdTables` lists the columns whose IDs the bootstrap rewrites
/// through the reference DB's `entity_aliases`. A column missing from it
/// keeps pointing at an ID the reference DB no longer has once two entities
/// are merged: the card, the cached photo or the name it belongs to silently
/// stops resolving. Nothing at runtime notices, because the stale row is
/// still a valid row — so the list is held against the schema assets here.
///
/// A column counts as a candidate by its name: `species_id`, `entity_id`,
/// `entity_key` and `taxon_id`/`taxon_key`, also with a prefix
/// (`owner_species_id`) or in the plural. A candidate is either rewritten —
/// by `referenceIdTables` or by a dedicated rewrite named in
/// [_rewrittenOutsideTheList] — or exempt for a reason in [_exempt].
///
/// Run with: flutter test test/architecture/reference_id_tables_coverage_test.dart
library;

import 'dart:io';

import 'package:discere/shared/persistence/reference_id/reference_id_tables.dart';
import 'package:discere/shared/persistence/reference_id/search_document_merge.dart';
import 'package:discere/shared/persistence/schema/schema_asset.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'arch_assertions.dart';

final _candidateColumn = RegExp(
  r'^(?:\w+_)?(?:species|entity|taxon)_(?:id|key)s?$',
);

/// The column a `KeyedIdTable.idSql` reads, e.g. `{t}.species_id` or
/// `substr({t}.entity_key, 9)`.
final _idSqlColumn = RegExp(r'\{t\}\.(\w+)');

/// Columns rewritten by something other than a `referenceIdTables` entry,
/// with what rewrites them.
const _rewrittenOutsideTheList = <String, String>{
  '$searchDocumentsTable.entity_id':
      'rewriteSearchDocumentEntityIds — not a key, so it needs no collision '
      'rule',
};

/// Candidate columns that never hold a reference ID.
const _exempt = <String, String>{
  'enrichment_taxonomy_work.runtime_entity_key':
      'always `rank:<scientificName>` — a higher taxon by name, which an '
      'alias does not change',
  'inat_photo_cache.inat_taxon_id':
      'an iNaturalist taxon id, the provenance stamp of the photos — not a '
      'reference ID',
  'runtime_common_names.inat_taxon_id':
      'an iNaturalist taxon id, the provenance stamp of the names — not a '
      'reference ID',
};

void main() {
  setUpAll(sqfliteFfiInit);

  test('every column that can hold a reference ID is rewritten', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    var readAssets = 0;
    final columns = <String>{};
    final candidates = <String>[];
    for (final path in UserDbSchema.schemaAssetPaths) {
      final asset = SchemaAsset.parse(await File(path).readAsString());
      readAssets++;
      // An FTS table holds only text the search documents feed into it.
      if (asset.isVirtual) continue;
      await db.execute(asset.createTable);
      final info = await db.rawQuery('PRAGMA table_info(${asset.tableName})');
      for (final column in info) {
        final qualified = '${asset.tableName}.${column['name']}';
        columns.add(qualified);
        if (_candidateColumn.hasMatch(column['name'] as String)) {
          candidates.add(qualified);
        }
      }
    }

    final listed = <String>{
      for (final table in referenceIdTables)
        for (final match in _idSqlColumn.allMatches(table.idSql))
          '${table.table}.${match.group(1)}',
    };

    expectScanFound(readAssets, 15, 'user-database schema assets');
    expectScanFound(candidates.length, 10, 'candidate reference-ID columns');
    expectScanFound(listed.length, 5, 'columns in referenceIdTables');

    final unlisted = [
      for (final column in candidates)
        if (!listed.contains(column) &&
            !_rewrittenOutsideTheList.containsKey(column) &&
            !_exempt.containsKey(column))
          column,
    ];
    expect(
      unlisted,
      isEmpty,
      reason:
          'ARCH-17: these columns can hold a reference ID, and nothing '
          'rewrites them when the reference DB merges two entities:\n'
          '  ${unlisted.join('\n  ')}\n'
          'Add the table to referenceIdTables '
          '(lib/shared/persistence/reference_id/reference_id_tables.dart) '
          'with its collision rule, and to the matrix in '
          'etl/docs/datenquellen.md. If the column never holds a reference '
          'ID, list it in _exempt in this file with the reason.',
    );

    final stale = [
      for (final column in {
        ...listed,
        ..._rewrittenOutsideTheList.keys,
        ..._exempt.keys,
      })
        if (!columns.contains(column)) column,
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'ARCH-17: these columns are rewritten or exempted, but no schema '
          'asset declares them — the table or column was renamed or '
          'dropped:\n  ${stale.join('\n  ')}',
    );
  });
}
