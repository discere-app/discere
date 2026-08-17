import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDeckRepository mockDeckRepository;
  late MockRemoteDeckService mockRemoteDeckService;
  late SharedPreferences preferences;
  late DeckUpdateService service;

  setUp(() async {
    mockDeckRepository = MockDeckRepository();
    mockRemoteDeckService = MockRemoteDeckService();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    service = DeckUpdateService(
      mockDeckRepository,
      mockRemoteDeckService,
      preferences,
    );
  });

  BaseDeck localDeck({
    required String id,
    String? sourceId,
    DateTime? updatedAt,
  }) => BaseDeck(id, 'Local $id', 'desc', sourceId: sourceId, updatedAt: updatedAt);

  CreateDeck remoteDeck({
    required String sourceId,
    required DateTime updatedAt,
  }) => CreateDeck(
    name: 'Remote $sourceId',
    description: 'desc',
    sourceId: sourceId,
    updatedAt: updatedAt,
  );

  group('DeckUpdateService', () {
    test('flags a deck whose catalog entry is newer', () async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final remote = remoteDeck(
        sourceId: 'src-1',
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      when(
        mockRemoteDeckService.fetchRemoteDecks(),
      ).thenAnswer((_) async => [remote]);

      await service.checkForUpdates();

      expect(service.updateFor('deck-1'), same(remote));
    });

    test('does not flag a deck that is already up to date', () async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 2, 1),
          ),
        ],
      );
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
        ],
      );

      await service.checkForUpdates();

      expect(service.updateFor('deck-1'), isNull);
    });

    test('treats a null local updatedAt as always outdated', () async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [localDeck(id: 'deck-1', sourceId: 'src-1')],
      );
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 1, 1)),
        ],
      );

      await service.checkForUpdates();

      expect(service.updateFor('deck-1'), isNotNull);
    });

    test('ignores decks without a sourceId and skips the catalog fetch', () async {
      when(
        mockDeckRepository.getAllDecks(),
      ).thenAnswer((_) async => [localDeck(id: 'deck-1')]);

      await service.checkForUpdates();

      expect(service.updateFor('deck-1'), isNull);
      verifyNever(mockRemoteDeckService.fetchRemoteDecks());
    });

    test('swallows a failed catalog fetch', () async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      when(
        mockRemoteDeckService.fetchRemoteDecks(),
      ).thenThrow(Exception('network down'));

      await service.checkForUpdates();

      expect(service.updateFor('deck-1'), isNull);
    });

    test('clearUpdate removes a pending update and notifies', () async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1)),
        ],
      );
      await service.checkForUpdates();
      expect(service.updateFor('deck-1'), isNotNull);

      var notified = false;
      service.addListener(() => notified = true);
      service.clearUpdate('deck-1');

      expect(service.updateFor('deck-1'), isNull);
      expect(notified, isTrue);
    });

    test('skips the catalog fetch when checked recently', () async {
      await preferences.setInt(
        'deck_update_last_checked_at',
        DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      );

      await service.checkForUpdates();

      verifyNever(mockDeckRepository.getAllDecks());
    });

    test('checks again once checkInterval has passed', () async {
      await preferences.setInt(
        'deck_update_last_checked_at',
        DateTime.now()
            .subtract(DeckUpdateService.checkInterval)
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1)),
        ],
      );

      await service.checkForUpdates();

      expect(service.updateFor('deck-1'), isNotNull);
    });

    test('force bypasses the throttle', () async {
      await preferences.setInt(
        'deck_update_last_checked_at',
        DateTime.now().millisecondsSinceEpoch,
      );
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          remoteDeck(sourceId: 'src-1', updatedAt: DateTime.utc(2026, 2, 1)),
        ],
      );

      await service.checkForUpdates(force: true);

      expect(service.updateFor('deck-1'), isNotNull);
    });

    test('a failed fetch does not reset the throttle timer', () async {
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      when(
        mockRemoteDeckService.fetchRemoteDecks(),
      ).thenThrow(Exception('network down'));

      await service.checkForUpdates();

      expect(preferences.getInt('deck_update_last_checked_at'), isNull);
    });
  });
}
