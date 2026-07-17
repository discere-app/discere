import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';

class DeckRepository {
  static final _log = Logger.forType(DeckRepository);
  static const bool _enableDeckDebugLogging = true;
  final Uuid _uuid = const Uuid();
  DeckRepository();

  Future<Database> get _database async => await DatabaseHelper.userDb;

  Future<String> insertDeck(BaseDeck deck) async {
    deck.id ??= _uuid.v4();
    _logDebug('Deck repo: insertDeck id=${deck.id} name="${deck.name}"');

    final db = await _database;
    final existing = await db.query(
      'decks',
      columns: ['sortOrder', 'sourceId', 'updatedAt'],
      where: 'id = ?',
      whereArgs: [deck.id],
      limit: 1,
    );

    // Editing a deck (e.g. via EditDeckPage) never touches sourceId/updatedAt,
    // so this is an upsert with those fields unset. Preserve whatever was
    // already stored instead of nulling them out via INSERT OR REPLACE.
    if (existing.isNotEmpty) {
      deck.sourceId ??= existing.first['sourceId'] as String?;
      final existingUpdatedAtMillis = existing.first['updatedAt'] as int?;
      deck.updatedAt ??= existingUpdatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(existingUpdatedAtMillis);
    }

    final sortOrder = await _resolveSortOrder(db, existing);
    await db.insert(
      'decks',
      _toMap(deck, sortOrder),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return deck.id!;
  }

  Future<List<BaseDeck>> getAllDecks() async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> result = await db.query(
      'decks',
      orderBy: 'sortOrder ASC',
    );
    stopwatch.stop();
    _logDebug(
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
    _logDebug(
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
    _logDebug('Deck repo: delete id=$deckId');
    db.delete('decks', where: 'id = ?', whereArgs: List.of({deckId}));
  }

  List<BaseDeck> _toBaseDecks(List<Map<String, dynamic>> maps) {
    var list = List.generate(maps.length, (i) {
      final updatedAtMillis = maps[i]['updatedAt'] as int?;
      return BaseDeck(
        maps[i]['id'],
        maps[i]['name'],
        maps[i]['description'],
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

  void _logDebug(String message) {
    if (_enableDeckDebugLogging) {
      _log.debug(message);
    }
  }
}
