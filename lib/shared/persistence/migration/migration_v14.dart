part of '../user_db_schema.dart';

/// Migration v13 → v14: adds `species_photo_gap_ack`, tracking per-deck
/// which species the user has already been informed about (and decided to
/// keep) after iNaturalist enrichment confirmed no photo could be found.
Future<void> migrateUserDbToV14(Database db) async {
  _log.debug('Migrating user DB v13 → v14: adding species_photo_gap_ack');
  // The v14 shape, frozen inline. It happens to match the current schema
  // asset — the table has not changed since it was introduced here — but it
  // is written out anyway, so a later change to that asset cannot silently
  // rewrite what this version created. A migration describes the schema as
  // it was.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS species_photo_gap_ack (
      deck_id         TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
      species_id      TEXT NOT NULL,
      acknowledged_at INTEGER NOT NULL,
      PRIMARY KEY (deck_id, species_id)
    )
    ''');
}
