part of '../user_db_schema.dart';

/// Migration to v5: drops flashcard_stats to remove legacy SM-2 columns
/// (interval, repetition, ease_factor). Only applies to dev installs — this
/// clears all review history.
Future<void> migrateUserDbToV5(Database db) async {
  await db.execute('DROP TABLE IF EXISTS flashcard_stats');
}
