import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchListService extends ChangeNotifier {
  static const watchlistKey = 'watchlist';
  late final SharedPreferences _prefs;
  Set<String> _items = {};
  final Completer<void> _initCompleter = Completer<void>();

  WatchListService(SharedPreferences prefs) {
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

  Set<String> getSpecies() {
    return _items;
  }

  void removeSpecies(String speciesId) {
    _items.remove(speciesId);
    updateSharedPrefsAndNotifyListeners();
  }

  void updateSharedPrefsAndNotifyListeners() {
    _prefs.setStringList(watchlistKey, _items.toList());
    notifyListeners();
  }
}
