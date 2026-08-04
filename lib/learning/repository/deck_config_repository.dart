import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class DeckConfigRepository {
  final Database? _injectedDb;

  DeckConfigRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Returns the config for [deckId], or defaults if none exists yet.
  ///
  /// [defaultRetention] is used as the desired-retention default when no row
  /// exists in the database (i.e. the deck has never been configured).
  Future<DeckConfig> getOrDefault(
    String deckId, {
    double defaultRetention = 0.9,
  }) async {
    final db = await _database;
    final result = await db.query(
      'deck_config',
      where: 'deck_id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    if (result.isEmpty) {
      return DeckConfig(deckId: deckId, desiredRetention: defaultRetention);
    }
    return DeckConfig.fromMap(result.first);
  }

  /// Inserts or replaces the config for a deck.
  Future<void> save(DeckConfig config) async {
    final db = await _database;
    await db.insert(
      'deck_config',
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
