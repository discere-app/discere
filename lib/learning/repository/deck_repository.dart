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
    final sortOrder = await _resolveSortOrder(db, deck.id!);
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

  /// Resolves the sortOrder to persist for [deckId]: preserves the existing
  /// value on update, or appends to the end of the list for a new deck.
  Future<int> _resolveSortOrder(Database db, String deckId) async {
    final existing = await db.query(
      'decks',
      columns: ['sortOrder'],
      where: 'id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['sortOrder'] as int;
    }

    final maxResult = await db.rawQuery(
      'SELECT MAX(sortOrder) AS maxSortOrder FROM decks',
    );
    final maxSortOrder = maxResult.first['maxSortOrder'] as int?;
    return (maxSortOrder ?? -1) + 1;
  }

  Future<void> delete(String deckId) async {
    final db = await _database;
    _logDebug('Deck repo: delete id=$deckId');
    db.delete('decks', where: 'id = ?', whereArgs: List.of({deckId}));
  }

  List<BaseDeck> _toBaseDecks(List<Map<String, dynamic>> maps) {
    var list = List.generate(maps.length, (i) {
      return BaseDeck(
        maps[i]['id'],
        maps[i]['name'],
        maps[i]['description'],
        coverImagePath: maps[i]['coverImagePath'],
        language: Language.fromValue(maps[i]['language'] ?? Language.en.value),
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
    };
  }

  void _logDebug(String message) {
    if (_enableDeckDebugLogging) {
      _log.debug(message);
    }
  }
}
