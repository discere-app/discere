import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// Repository for managing mappings between internal species UUIDs
/// and external platform identifiers (e.g., iNaturalist Taxon ID).
class ExternalIdRepository {
  static const tableName = 'external_identifiers';

  final Database? _injectedDb;
  final Database? _injectedRefDb;

  ExternalIdRepository({Database? database, Database? referenceDatabase})
      : _injectedDb = database,
        _injectedRefDb = referenceDatabase;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  Future<Database> get _referenceDb async =>
      _injectedRefDb ?? await DatabaseHelper.referenceDb;

  /// Returns the external identifier for a given entity and provider.
  Future<String?> getExternalId(String entityId, String provider) async {
    final db = await _database;
    final rows = await db.query(
      tableName,
      columns: ['external_id'],
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['external_id'] as String?;
  }

  /// Saves or updates an external identifier mapping.
  Future<void> saveExternalId(String entityId, String provider, String externalId) async {
    final db = await _database;
    await db.insert(
      tableName,
      {
        'entity_id': entityId,
        'provider': provider,
        'external_id': externalId,
        'last_synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a mapping for a specific provider.
  Future<void> deleteExternalId(String entityId, String provider) async {
    final db = await _database;
    await db.delete(
      tableName,
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider],
    );
  }

  /// Returns the iNaturalist taxon_id from the reference DB (populated by ETL enrichment).
  /// Returns null if the species has no pre-resolved mapping.
  Future<int?> getINatTaxonId(String speciesId) async {
    try {
      final db = await _referenceDb;
      final rows = await db.query(
        'inat_taxon_ids',
        columns: ['taxon_id'],
        where: 'species_id = ?',
        whereArgs: [speciesId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['taxon_id'] as int?;
    } catch (_) {
      // Table may not exist in older reference DBs
      return null;
    }
  }
}
