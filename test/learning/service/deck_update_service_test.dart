import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDeckRepository mockDeckRepository;
  late MockRemoteDeckService mockRemoteDeckService;
  late DeckUpdateService service;

  setUp(() {
    mockDeckRepository = MockDeckRepository();
    mockRemoteDeckService = MockRemoteDeckService();
    service = DeckUpdateService(mockDeckRepository, mockRemoteDeckService);
  });

  BaseDeck localDeck({
    required String id,
    String? sourceId,
    DateTime? updatedAt,
  }) => BaseDeck(
  id: id,
  name: 'Local $id',
  description: 'desc', sourceId: sourceId, updatedAt: updatedAt);

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

    test('every check fetches the catalog, so each session knows the '
        'update', () async {
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
      final nextSession = DeckUpdateService(
        mockDeckRepository,
        mockRemoteDeckService,
      );
      await nextSession.checkForUpdates();

      verify(mockRemoteDeckService.fetchRemoteDecks()).called(2);
      expect(nextSession.updateFor('deck-1'), same(remote));
    });

    test('an update applied in one session is not offered again in the '
        'next', () async {
      final catalogUpdatedAt = DateTime.utc(2026, 2, 1);
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          remoteDeck(sourceId: 'src-1', updatedAt: catalogUpdatedAt),
        ],
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
      await service.checkForUpdates();
      expect(service.updateFor('deck-1'), isNotNull);

      // Applying an update stamps the local deck with the catalog entry's
      // updatedAt (DeckUpdateApplier.apply).
      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [
          localDeck(
            id: 'deck-1',
            sourceId: 'src-1',
            updatedAt: catalogUpdatedAt,
          ),
        ],
      );
      final nextSession = DeckUpdateService(
        mockDeckRepository,
        mockRemoteDeckService,
      );
      await nextSession.checkForUpdates();

      expect(nextSession.updateFor('deck-1'), isNull);
    });

    test('a superseded deck is offered for merging instead of an update, '
        'until the merge has deleted it', () async {
      final old = localDeck(id: 'deck-old', sourceId: 'src-old');
      final updated = remoteDeck(
        sourceId: 'src-old',
        updatedAt: DateTime.utc(2026, 2, 1),
      );
      final successor = CreateDeck(
        name: 'Successor',
        description: 'desc',
        sourceId: 'src-new',
        supersedes: ['src-old'],
      );
      when(mockDeckRepository.getAllDecks()).thenAnswer((_) async => [old]);
      when(
        mockRemoteDeckService.fetchRemoteDecks(),
      ).thenAnswer((_) async => [updated, successor]);

      await service.checkForUpdates();

      expect(service.replacementFor('deck-old'), same(successor));
      expect(service.updateFor('deck-old'), isNull);
      expect(service.catalog, [updated, successor]);

      when(mockDeckRepository.getAllDecks()).thenAnswer(
        (_) async => [localDeck(id: 'deck-new', sourceId: 'src-new')],
      );
      await service.reconcileWithLocalDecks();

      expect(service.replacementFor('deck-old'), isNull);
      expect(service.replacementFor('deck-new'), isNull);
    });
  });
}
