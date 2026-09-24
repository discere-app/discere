import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DeckRepository {
  static final _log = Logger.forType(DeckRepository);
  final Uuid _uuid = const Uuid();
  final Database? _injectedDb;

  DeckRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Upserts [deck] and returns the id it was stored under — a new one when
  /// the deck did not carry one.
  ///
  /// The deck passed in is left alone; what gets written is the local copy
  /// built here. Callers that need the id take the return value.
  Future<String> insertDeck(BaseDeck deck) async {
    final id = deck.id ?? _uuid.v4();
    _log.debug('Deck repo: insertDeck id=$id name="${deck.name}"');

    final db = await _database;
    final existing = await db.query(
      'decks',
      columns: ['sortOrder', 'sourceId', 'updatedAt'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    // Editing a deck (e.g. via EditDeckPage) never touches sourceId/updatedAt,
    // so this is an upsert with those fields unset. Preserve whatever was
    // already stored instead of nulling them out via INSERT OR REPLACE.
    final existingUpdatedAtMillis = existing.isEmpty
        ? null
        : existing.first['updatedAt'] as int?;
    final stored = deck.copyWith(
      id: id,
      sourceId: existing.isEmpty
          ? null
          : existing.first['sourceId'] as String?,
      updatedAt: existingUpdatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(existingUpdatedAtMillis),
    );

    final sortOrder = await _resolveSortOrder(db, existing);
    final map = _toMap(stored, sortOrder);
    if (existing.isNotEmpty) {
      // A real UPDATE, not INSERT OR REPLACE: SQLite implements the latter
      // as DELETE-then-INSERT, which fires flashcard_stats'/deck_config's/
      // daily_counts' ON DELETE CASCADE to decks(id) now that foreign-key
      // enforcement is actually on — wiping a deck's entire review progress
      // just from touching an unrelated column like coverImagePath.
      await db.update('decks', map, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert('decks', map);
    }
    return id;
  }

  Future<List<BaseDeck>> getAllDecks() async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> result = await db.query(
      'decks',
      orderBy: 'sortOrder ASC',
    );
    stopwatch.stop();
    _log.debug(
      'Deck repo: getAllDecks rows=${result.length} '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
    return _toBaseDecks(result);
  }

  Future<List<BaseDeck>> getDecksByIds(Set<String> deckIds) async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> result = await db.query(
      'decks',
      where: 'id IN (${List.generate(deckIds.length, (_) => '?').join(',')})',
      whereArgs: deckIds.toList(),
      orderBy: 'sortOrder ASC',
    );
    stopwatch.stop();
    _log.debug(
      'Deck repo: getDecksByIds ids=${deckIds.length} rows=${result.length} '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    return _toBaseDecks(result);
  }

  /// Resolves the sortOrder to persist, given the existing row (if any) for
  /// this deck id: preserves the existing value on update, or appends to the
  /// end of the list for a new deck.
  Future<int> _resolveSortOrder(
    Database db,
    List<Map<String, dynamic>> existing,
  ) async {
    if (existing.isNotEmpty) {
      return existing.first['sortOrder'] as int;
    }

    final maxResult = await db.rawQuery(
      'SELECT MAX(sortOrder) AS maxSortOrder FROM decks',
    );
    final maxSortOrder = maxResult.first['maxSortOrder'] as int?;
    return (maxSortOrder ?? -1) + 1;
  }

  /// Sets sourceId/updatedAt directly, without touching any other column.
  /// Only used by [DeckSourceIdBackfillService] — a plain [insertDeck]
  /// upsert would also work, but this avoids re-resolving sortOrder for a
  /// field-only update. Remove alongside that service; see its class doc.
  @Deprecated(
    'Only used by the temporary DeckSourceIdBackfillService (1.0.4 rollout). '
    'Remove alongside it once that service is deleted.',
  )
  Future<void> updateSourceMetadata(
    String deckId, {
    required String sourceId,
    DateTime? updatedAt,
  }) async {
    final db = await _database;
    await db.update(
      'decks',
      {'sourceId': sourceId, 'updatedAt': updatedAt?.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [deckId],
    );
  }

  Future<void> delete(String deckId) async {
    final db = await _database;
    _log.debug('Deck repo: delete id=$deckId');
    await db.delete('decks', where: 'id = ?', whereArgs: [deckId]);
  }

  List<BaseDeck> _toBaseDecks(List<Map<String, dynamic>> maps) {
    var list = List.generate(maps.length, (i) {
      final updatedAtMillis = maps[i]['updatedAt'] as int?;
      return BaseDeck(
  id: maps[i]['id'],
  name: maps[i]['name'],
  description: maps[i]['description'],
        coverImagePath: maps[i]['coverImagePath'],
        language: Language.fromValue(maps[i]['language'] ?? Language.en.value),
        sourceId: maps[i]['sourceId'],
        updatedAt: updatedAtMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
      );
    });
    return list;
  }

  Map<String, dynamic> _toMap(BaseDeck deck, int sortOrder) {
    return {
      'id': deck.id,
      'name': deck.name,
      'description': deck.description,
      'coverImagePath': deck.coverImagePath,
      'language': deck.language.value,
      'sortOrder': sortOrder,
      'sourceId': deck.sourceId,
      'updatedAt': deck.updatedAt?.millisecondsSinceEpoch,
    };
  }

}
