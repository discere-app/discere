import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService extends ChangeNotifier {
  static const String _decksKey = 'favoriteDecks';
  late final SharedPreferences _prefs;
  late Set<String> _favoriteDecks;
  final Completer<void> _initCompleter = Completer<void>();

  FavoriteService(SharedPreferences sharedPreferences) {
    _prefs = sharedPreferences;
    _init();
  }

  Future<void> _init() async {
    _favoriteDecks = _prefs.getStringList(_decksKey)?.toSet() ?? {};
    _initCompleter.complete();
  }

  Set<String> getDecks() {
    _ensureInitialized();
    return _favoriteDecks;
  }

  void toggleDeck(String deckId) {
    _ensureInitialized();
    if (_favoriteDecks.contains(deckId)) {
      _favoriteDecks.remove(deckId);
    } else {
      _favoriteDecks.add(deckId);
    }
    _saveDecks();
    notifyListeners();
  }

  Future<void> _ensureInitialized() async {
    await _initCompleter.future;
  }

  void _saveDecks() {
    _prefs.setStringList(_decksKey, _favoriteDecks.toList());
  }

  isFavoriteDeck(String deckId) {
    return _favoriteDecks.contains(deckId);
  }
}
