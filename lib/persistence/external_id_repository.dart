import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// Repository for managing mappings between internal species UUIDs
/// and external platform identifiers (e.g., iNaturalist Taxon ID).
class ExternalIdRepository {
  static const tableName = 'external_identifiers';

  final Database? _injectedDb;

  ExternalIdRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

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
}
