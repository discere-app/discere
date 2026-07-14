import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesService extends ChangeNotifier {
  static const String _hasSeenWelcomeDialogKey = 'has_seen_welcome_dialog';
  static const String _hasSeenTutorialKey = 'has_seen_tutorial';
  static const String _hasSeenFlashcardTutorialKey = 'has_seen_flashcard_tutorial';
  static const String _defaultDesiredRetentionKey = 'default_desired_retention';
  static const String _notificationHourKey = 'notification_hour';
  static const String _notificationMinuteKey = 'notification_minute';

  final SharedPreferences _prefs;

  UserPreferencesService(this._prefs);

  bool get hasSeenWelcomeDialog {
    return _prefs.getBool(_hasSeenWelcomeDialogKey) ?? false;
  }

  set hasSeenWelcomeDialog(bool value) {
    _prefs.setBool(_hasSeenWelcomeDialogKey, value);
    notifyListeners();
  }

  bool get hasSeenTutorial {
    return _prefs.getBool(_hasSeenTutorialKey) ?? false;
  }

  set hasSeenTutorial(bool value) {
    _prefs.setBool(_hasSeenTutorialKey, value);
    notifyListeners();
  }

  bool get hasSeenFlashcardTutorial {
    return _prefs.getBool(_hasSeenFlashcardTutorialKey) ?? false;
  }

  set hasSeenFlashcardTutorial(bool value) {
    _prefs.setBool(_hasSeenFlashcardTutorialKey, value);
    notifyListeners();
  }

  /// Global default for desired retention (0.70–0.97).
  /// Used as the fallback when a deck has no saved config.
  double get defaultDesiredRetention {
    return _prefs.getDouble(_defaultDesiredRetentionKey) ?? 0.9;
  }

  set defaultDesiredRetention(double value) {
    _prefs.setDouble(_defaultDesiredRetentionKey, value);
    notifyListeners();
  }

  /// Hour of day (0-23) at which daily review reminders are scheduled.
  int get notificationHour {
    return _prefs.getInt(_notificationHourKey) ?? 19;
  }

  set notificationHour(int value) {
    _prefs.setInt(_notificationHourKey, value);
    notifyListeners();
  }

  /// Minute of the hour (0-59) at which daily review reminders are scheduled.
  int get notificationMinute {
    return _prefs.getInt(_notificationMinuteKey) ?? 0;
  }

  set notificationMinute(int value) {
    _prefs.setInt(_notificationMinuteKey, value);
    notifyListeners();
  }
}
