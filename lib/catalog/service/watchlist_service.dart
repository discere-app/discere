import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchlistService extends ChangeNotifier {
  static const watchlistKey = 'watchlist';
  late final SharedPreferences _prefs;
  Set<String> _items = {};
  final Completer<void> _initCompleter = Completer<void>();

  WatchlistService(SharedPreferences prefs) {
    _prefs = prefs;
    _init();
  }

  Future<void> _init() async {
    _items = _prefs.getStringList(watchlistKey)?.toSet() ?? {};
    notifyListeners();
    _initCompleter.complete();
  }

  void addSpecies(String speciesId) {
    _items.add(speciesId);
    updateSharedPrefsAndNotifyListeners();
  }

  bool containsSpecies(String speciesId) {
    return _items.contains(speciesId);
  }

  Set<String> getSpecies() {
    return _items;
  }

  void removeSpecies(String speciesId) {
    _items.remove(speciesId);
    updateSharedPrefsAndNotifyListeners();
  }

  void toggleSpecies(String speciesId) {
    if (containsSpecies(speciesId)) {
      removeSpecies(speciesId);
    } else {
      addSpecies(speciesId);
    }
  }

  void updateSharedPrefsAndNotifyListeners() {
    _prefs.setStringList(watchlistKey, _items.toList());
    notifyListeners();
  }
}
