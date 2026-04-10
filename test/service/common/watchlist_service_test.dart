import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockSharedPreferences mockPrefs;
  late WatchListService service;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    // Default: no existing watchlist saved.
    when(mockPrefs.getStringList(WatchListService.watchlistKey))
        .thenReturn(null);
    when(mockPrefs.setStringList(any, any)).thenAnswer((_) async => true);
    service = WatchListService(mockPrefs);
  });

  group('WatchListService', () {
    test('starts with an empty list when no prefs data exists', () {
      expect(service.getSpecies(), isEmpty);
    });

    test('loads existing watchlist from SharedPreferences on init', () {
      when(mockPrefs.getStringList(WatchListService.watchlistKey))
          .thenReturn(['42', '99']);
      final freshService = WatchListService(mockPrefs);

      expect(freshService.getSpecies(), containsAll(['42', '99']));
    });

    test('addSpecies adds a species to the in-memory set', () {
      service.addSpecies('123');

      expect(service.getSpecies(), contains('123'));
    });

    test('addSpecies persists the new species to SharedPreferences', () {
      service.addSpecies('123');

      verify(mockPrefs.setStringList(
        WatchListService.watchlistKey,
        argThat(contains('123')),
      )).called(1);
    });

    test('removeSpecies removes a species from the in-memory set', () {
      service.addSpecies('123');
      service.removeSpecies('123');

      expect(service.getSpecies(), isNot(contains('123')));
    });

    test('removeSpecies persists the updated list to SharedPreferences', () {
      service.addSpecies('123');
      clearInteractions(mockPrefs);

      service.removeSpecies('123');

      verify(mockPrefs.setStringList(
        WatchListService.watchlistKey,
        argThat(isNot(contains('123'))),
      )).called(1);
    });

    test('addSpecies notifies listeners', () {
      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      service.addSpecies('123');

      expect(notificationCount, 1);
    });

    test('removeSpecies notifies listeners', () {
      service.addSpecies('123');
      int notificationCount = 0;
      service.addListener(() => notificationCount++);

      service.removeSpecies('123');

      expect(notificationCount, 1);
    });

    test('adding the same species twice keeps only one entry', () {
      service.addSpecies('123');
      service.addSpecies('123');

      expect(service.getSpecies().length, 1);
    });
  });
}
