import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// User-DB cache for runtime-discovered external identifiers.
///
/// These mappings are opportunistic fallbacks and not the authoritative source
/// of truth. Curated ETL mappings live in the reference DB.
class ExternalIdCacheRepository {
  static const tableName = 'external_identifier_cache';

  final Database? _injectedDb;

  ExternalIdCacheRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

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

  Future<void> saveExternalId(
    String entityId,
    String provider,
    String externalId,
  ) async {
    final db = await _database;
    await db.insert(tableName, {
      'entity_id': entityId,
      'provider': provider,
      'external_id': externalId,
      'last_synced_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteExternalId(String entityId, String provider) async {
    final db = await _database;
    await db.delete(
      tableName,
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider],
    );
  }
}
