import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesService extends ChangeNotifier {
  static const String _hasSeenWelcomeDialogKey = 'has_seen_welcome_dialog';
  final SharedPreferences _prefs;

  UserPreferencesService(this._prefs);

  bool get hasSeenWelcomeDialog {
    return _prefs.getBool(_hasSeenWelcomeDialogKey) ?? false;
  }

  set hasSeenWelcomeDialog(bool value) {
    _prefs.setBool(_hasSeenWelcomeDialogKey, value);
    notifyListeners();
  }
}
