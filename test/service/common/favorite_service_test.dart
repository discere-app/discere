import 'package:discere/learning/service/favorite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockSharedPreferences mockPrefs;
  late FavoriteService service;

  const decksKey = 'favoriteDecks';

  setUp(() {
    mockPrefs = MockSharedPreferences();
    // Default: no existing favorites saved.
    when(mockPrefs.getStringList(decksKey)).thenReturn(null);
    when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);
    service = FavoriteService(mockPrefs);
  });

  group('FavoriteService', () {
    test('starts with an empty favorites set when no prefs data exists', () {
      expect(service.getDecks(), isEmpty);
    });

    test('loads existing favorites from SharedPreferences on init', () {
      when(mockPrefs.getStringList(decksKey)).thenReturn(['deck1', 'deck2']);
      final freshService = FavoriteService(mockPrefs);

      expect(freshService.getDecks(), containsAll(['deck1', 'deck2']));
    });

    test('toggleDeck adds a deck that is not yet a favorite', () {
      service.toggleDeck('deck1');

      expect(service.getDecks(), contains('deck1'));
    });

    test('toggleDeck removes a deck that is already a favorite', () {
      service.toggleDeck('deck1');
      service.toggleDeck('deck1');

      expect(service.getDecks(), isNot(contains('deck1')));
    });

    test('toggleDeck persists to SharedPreferences when adding', () {
      service.toggleDeck('deck1');

      verify(
        mockPrefs.setStringList(decksKey, argThat(contains('deck1'))),
      ).called(1);
    });

    test('toggleDeck persists to SharedPreferences when removing', () {
      service.toggleDeck('deck1');
      clearInteractions(mockPrefs);

      service.toggleDeck('deck1');

      verify(
        mockPrefs.setStringList(decksKey, argThat(isNot(contains('deck1')))),
      ).called(1);
    });

    test('isFavoriteDeck returns true for a favorited deck', () {
      service.toggleDeck('deck1');

      expect(service.isFavoriteDeck('deck1'), isTrue);
    });

    test('isFavoriteDeck returns false for a non-favorited deck', () {
      expect(service.isFavoriteDeck('deck1'), isFalse);
    });

    test('toggleDeck notifies listeners', () {
      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      service.toggleDeck('deck1');

      expect(notificationCount, 1);
    });

    test('toggleDeck notifies listeners on remove', () {
      service.toggleDeck('deck1');
      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      service.toggleDeck('deck1');

      expect(notificationCount, 1);
    });
  });
}
