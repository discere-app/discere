import 'package:sqflite/sqflite.dart';

import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';

/// User-DB cache for runtime-discovered external identifiers.
///
/// These mappings are opportunistic fallbacks and not the authoritative source
/// of truth. Curated ETL mappings live in the reference DB.
class ExternalIdCacheRepository {
  static final _log = Logger.forType(ExternalIdCacheRepository);
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
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: external id cache start '
      '(entity=$entityId, provider=$provider)',
    );
    try {
      await db.insert(tableName, {
        'entity_id': entityId,
        'provider': provider,
        'external_id': externalId,
        'last_synced_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: external id cache done '
        '(entity=$entityId, provider=$provider, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<void> deleteExternalId(String entityId, String provider) async {
    final db = await _database;
    await db.delete(
      tableName,
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider],
    );
  }

  void _logDebug(String message) {
    _log.debug(message);
  }
}
