import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/language.dart';

class LanguageService extends ChangeNotifier {
  static const sharedPreferencesLanguageKey = 'language';
  final SharedPreferences _prefs;

  LanguageService(this._prefs);

  Language getLanguage() {
    return Language.fromValue(
        _prefs.getInt(sharedPreferencesLanguageKey) ?? Language.en.value);
  }

  void setLanguage(int language) {
    _prefs.setInt(sharedPreferencesLanguageKey, language);
    notifyListeners();
  }
}
