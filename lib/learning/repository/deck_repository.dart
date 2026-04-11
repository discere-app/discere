import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/shared/persistence/database_helper.dart';

class DeckRepository {
  static const bool _enableDeckDebugLogging = true;
  final Uuid _uuid = const Uuid();
  DeckRepository();

  Future<Database> get _database async => await DatabaseHelper.userDb;

  Future<String> insertDeck(BaseDeck deck) async {
    deck.id ??= _uuid.v4();

    final db = await _database;
    await db.insert(
      'decks',
      _toMap(deck),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return deck.id!;
  }

  Future<List<BaseDeck>> getAllDecks() async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> result = await db.query('decks');
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
    );
    stopwatch.stop();
    _logDebug(
      'Deck repo: getDecksByIds ids=${deckIds.length} rows=${result.length} '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    return _toBaseDecks(result);
  }

  Future<void> delete(String deckId) async {
    final db = await _database;
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

  Map<String, dynamic> _toMap(BaseDeck deck) {
    return {
      'id': deck.id,
      'name': deck.name,
      'description': deck.description,
      'coverImagePath': deck.coverImagePath,
      'language': deck.language.value,
    };
  }

  void _logDebug(String message) {
    if (_enableDeckDebugLogging && kDebugMode) {
      debugPrint(message);
    }
  }
}
