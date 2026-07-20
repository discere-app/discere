import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

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

  static const _batchChunkSize = 500;

  /// Returns cached taxon IDs for a batch of entities, keyed by entity ID.
  ///
  /// Only entries that parse as integers are included. Queries in chunks of
  /// [_batchChunkSize] to stay well within SQLite's 999-parameter limit.
  Future<Map<String, int>> getExternalIdsForProvider(
    Set<String> entityIds,
    ExternalIdProvider provider,
  ) async {
    if (entityIds.isEmpty) return const {};
    final db = await _database;
    final ids = entityIds.toList();
    final result = <String, int>{};
    for (var i = 0; i < ids.length; i += _batchChunkSize) {
      final chunk = ids.sublist(
        i,
        i + _batchChunkSize > ids.length ? ids.length : i + _batchChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT entity_id, external_id FROM $tableName '
        'WHERE provider = ? AND entity_id IN ($placeholders)',
        [provider.name, ...chunk],
      );
      for (final row in rows) {
        final id = int.tryParse(row['external_id'] as String? ?? '');
        if (id != null) result[row['entity_id'] as String] = id;
      }
    }
    return result;
  }

  /// Returns cached raw string values for a batch of entities, keyed by
  /// entity ID. Unlike [getExternalIdsForProvider], values are not parsed as
  /// integers — needed for providers whose cached value is a non-numeric
  /// code (e.g. IUCN status letters like "lc", "en"). Cache-only: entities
  /// with no cache entry are simply absent from the result, no network
  /// fallback is attempted.
  Future<Map<String, String>> getRawExternalIdsForProvider(
    Set<String> entityIds,
    ExternalIdProvider provider,
  ) async {
    if (entityIds.isEmpty) return const {};
    final db = await _database;
    final ids = entityIds.toList();
    final result = <String, String>{};
    for (var i = 0; i < ids.length; i += _batchChunkSize) {
      final chunk = ids.sublist(
        i,
        i + _batchChunkSize > ids.length ? ids.length : i + _batchChunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT entity_id, external_id FROM $tableName '
        'WHERE provider = ? AND entity_id IN ($placeholders)',
        [provider.name, ...chunk],
      );
      for (final row in rows) {
        final value = row['external_id'] as String?;
        if (value != null && value.isNotEmpty) {
          result[row['entity_id'] as String] = value;
        }
      }
    }
    return result;
  }

  Future<String?> getExternalId(
    String entityId,
    ExternalIdProvider provider,
  ) async {
    final db = await _database;
    final rows = await db.query(
      tableName,
      columns: ['external_id'],
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider.name],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['external_id'] as String?;
  }

  Future<void> saveExternalId(
    String entityId,
    ExternalIdProvider provider,
    String externalId,
  ) async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: external id cache start '
      '(entity=$entityId, provider=${provider.name})',
    );
    try {
      await db.insert(tableName, {
        'entity_id': entityId,
        'provider': provider.name,
        'external_id': externalId,
        'last_synced_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: external id cache done '
        '(entity=$entityId, provider=${provider.name}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<void> deleteExternalId(
    String entityId,
    ExternalIdProvider provider,
  ) async {
    final db = await _database;
    await db.delete(
      tableName,
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityId, provider.name],
    );
  }

  void _logDebug(String message) {
    _log.debug(message);
  }
}
