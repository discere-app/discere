part of '../user_db_schema.dart';

/// Migration v2 → v3: Add deck_config table for per-deck SRS settings.
Future<void> migrateUserDbToV3(Database db) async {
  _log.debug('Migrating user DB v2 → v3: adding deck_config table');
  await _executeSqlAsset(db, _createDeckConfigSqlAsset);
}
