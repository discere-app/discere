import 'package:discere/model/language.dart';
import 'package:discere/service/common/language_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSharedPreferences mockPrefs;
  late LanguageService service;

  const languageKey = LanguageService.sharedPreferencesLanguageKey;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    when(mockPrefs.setInt(any, any)).thenAnswer((_) async => true);
    service = LanguageService(mockPrefs);
  });

  group('LanguageService.getLanguage', () {
    test('returns Language.en as default when no preference is stored', () {
      when(mockPrefs.getInt(languageKey)).thenReturn(null);

      expect(service.getLanguage(), Language.en);
    });

    test('returns Language.de when pref is set to 0', () {
      when(mockPrefs.getInt(languageKey)).thenReturn(Language.de.value);

      expect(service.getLanguage(), Language.de);
    });

    test('returns Language.fr when pref is set to 2', () {
      when(mockPrefs.getInt(languageKey)).thenReturn(Language.fr.value);

      expect(service.getLanguage(), Language.fr);
    });

    test('returns Language.es when pref is set to 3', () {
      when(mockPrefs.getInt(languageKey)).thenReturn(Language.es.value);

      expect(service.getLanguage(), Language.es);
    });
  });

  group('LanguageService.setLanguage', () {
    test('persists the value to SharedPreferences with the correct key', () {
      service.setLanguage(Language.de.value);

      verify(mockPrefs.setInt(languageKey, Language.de.value)).called(1);
    });

    test('persists a different language value correctly', () {
      service.setLanguage(Language.fr.value);

      verify(mockPrefs.setInt(languageKey, Language.fr.value)).called(1);
    });

    test('notifies listeners after setting a new language', () {
      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      service.setLanguage(Language.de.value);

      expect(notificationCount, 1);
    });

    test('notifies listeners on every call, even with the same value', () {
      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      service.setLanguage(Language.en.value);
      service.setLanguage(Language.en.value);

      expect(notificationCount, 2);
    });
  });
}
