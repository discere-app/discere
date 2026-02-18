import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../model/learning/base_deck.dart';
import 'package:uuid/uuid.dart';

class DeckRepository {
  final Database _database;
  final Uuid _uuid = const Uuid();
  DeckRepository(this._database);

  Future<String> insertDeck(BaseDeck deck) async {
    deck.id ??= _uuid.v4();

    if (kDebugMode) {
      print('''
    --create new deck--
    id: ${deck.id}
    name: ${deck.name}
    ''');
    }
    await _database.insert('decks', _toMap(deck),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return deck.id!;
  }

  Future<List<BaseDeck>> getAllDecks() async {
    final List<Map<String, dynamic>> result = await _database.query('decks');
    return _toBaseDecks(result);
  }

  Future<List<BaseDeck>> getDecksByIds(Set<String> deckIds) async {
    final List<Map<String, dynamic>> result = await _database.query(
      'decks',
      where: 'id IN (${List.generate(deckIds.length, (_) => '?').join(',')})',
      whereArgs: deckIds.toList(),
    );

    return _toBaseDecks(result);
  }

  Future<void> delete(String deckId) async {
    _database.delete('decks', where: 'id = ?', whereArgs: List.of({deckId}));
  }

  List<BaseDeck> _toBaseDecks(List<Map<String, dynamic>> maps) {
    var list = List.generate(maps.length, (i) {
      return BaseDeck(maps[i]['id'], maps[i]['name'], maps[i]['description']);
    });
    return list;
  }

  Map<String, dynamic> _toMap(BaseDeck deck) {
    return {
      'id': deck.id,
      'name': deck.name,
      'description': deck.description,
    };
  }
}
