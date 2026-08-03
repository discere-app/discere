part of '../user_db_schema.dart';

/// Migration v13 → v14: adds `species_photo_gap_ack`, tracking per-deck
/// which species the user has already been informed about (and decided to
/// keep) after iNaturalist enrichment confirmed no photo could be found.
Future<void> migrateUserDbToV14(Database db) async {
  _log.debug('Migrating user DB v13 → v14: adding species_photo_gap_ack');
  await _executeSqlAsset(db, _createSpeciesPhotoGapAckSqlAsset);
}
